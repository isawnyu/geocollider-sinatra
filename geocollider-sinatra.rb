#!/usr/bin/env ruby

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/multi_route'
require 'tempfile'
require 'haml'
require 'geocollider'
require 'rest-client'
require 'json'

# JS/CSS asset management
require 'sprockets'
require 'uglifier'
require 'sass'
require 'coffee-script'
require 'execjs'

require_relative './lib/pleiades_parse_job.rb'
require_relative './lib/jsonp.rb'

def airbrake_enabled?
  File.exist?('airbrake.yml') || (ENV['AIRBRAKE_PROJECT_ID'] && ENV['AIRBRAKE_PROJECT_KEY'])
end

# Airbrake
if airbrake_enabled?
  $stderr.puts 'Configuring Airbrake...'

  require 'airbrake'
  require 'yaml'

  airbrake_config = {}
  if File.exist?('airbrake.yml')
    airbrake_config = YAML.load_file('airbrake.yml')
  else
    airbrake_config[:project_id] = ENV['AIRBRAKE_PROJECT_ID']
    airbrake_config[:project_key] = ENV['AIRBRAKE_PROJECT_KEY']
    if ENV.key?('AIRBRAKE_HOST')
      airbrake_config[:host] = ENV['AIRBRAKE_HOST']
    end
  end

  Airbrake.configure do |c|
    c.project_id = airbrake_config[:project_id]
    c.project_key = airbrake_config[:project_key]

    # Display debug output.
    c.logger.level = Logger::DEBUG
  end
end

class GeocolliderSinatra < Sinatra::Base
  helpers Sinatra::Jsonp
  register Sinatra::MultiRoute

  LATITUDE_PID = 'http://www.w3.org/2003/01/geo/wgs84_pos#lat'
  LONGITUDE_PID = 'http://www.w3.org/2003/01/geo/wgs84_pos#long'

  if airbrake_enabled?
    $stderr.puts 'Using Airbrake middleware...'
    use Airbrake::Rack::Middleware
  end

  NORMALIZATION_DEFAULTS = %w{whitespace case accents punctuation nfc}

  def initialize
    super()
    @pleiades = Geocollider::Parsers::PleiadesParser.new()
    @pleiades_parses = {}
    @tempfiles = []
    parse_pleiades(NORMALIZATION_DEFAULTS, true)
  end

  helpers do
    def parse_pleiades(normalizations, async = false)
      normalizations.sort!
      string_normalizer_lambda = Geocollider::StringNormalizer.normalizer_lambda(normalizations)
      if async
        PleiadesParseJob.perform_async(@pleiades_parses, @pleiades, Geocollider::Parsers::PleiadesParser::FILENAMES, string_normalizer_lambda, normalizations)
      else
        PleiadesParseJob.new.perform(@pleiades_parses, @pleiades, Geocollider::Parsers::PleiadesParser::FILENAMES, string_normalizer_lambda, normalizations)
      end
      return @pleiades_parses[normalizations]
    end
  end

  # initialize new sprockets environment
  set :environment, Sprockets::Environment.new

  # append assets paths
  environment.append_path "assets/stylesheets"
  environment.append_path "assets/javascripts"

  # compress assets
  environment.js_compressor  = :uglify
  environment.css_compressor = :scss

  environment.context_class.class_eval do
    def asset_path(path, options = {})
      "/assets/#{path}"
    end
  end

  # get assets
  get "/assets/*" do
    env["PATH_INFO"].sub!("/assets", "")
    settings.environment.call(env)
  end

  not_found do
    status 404
    @error_message = 'The requested URL could not be found.'
    haml :error
  end

  error Exception do
    status 500
    @error_message = 'There was an error processing your request. This error has been logged for investigation.'
    haml :error
  end

  get '/' do
    @reconciliation_endpoint = request.base_url + "/reconcile"
    haml :upload
  end

  get '/upload' do
    haml :upload
  end

  post '/upload' do
    $stderr.puts params['csvfile'][:filename]
    upload_basename = File.basename(params['csvfile'][:filename], File.extname(params['csvfile'][:filename]))
    $stderr.puts upload_basename
    tempfile_file = Tempfile.new([upload_basename + '_','.csv'])
    tempfile_file.close
    @tempfiles << tempfile_file # prevent GC/deletion until we close
    @uploaded_filename = tempfile_file.path
    $stderr.puts @uploaded_filename
    File.open(@uploaded_filename, "wb") do |f|
      f.write(params['csvfile'][:tempfile].read)
    end

    @csv_preview = File.open(@uploaded_filename,"r:bom|utf-8").read.force_encoding('UTF-8').encode('UTF-8', :invalid => :replace, :universal_newline => true).lines().first(3).join("\n").squeeze("\n")
    haml :post_upload
  end

  post '/process' do
    $stderr.puts params.inspect

    begin
      csv_options = {
        :separator => params['separator'] == 'tab' ? "\t" : ',',
        :quote_char => params['quote_char'].empty? ? "\u{FFFF}" : params['quote_char'],
        :names => params['names'].split(','),
        :lat => params['lat'],
        :lon => params['lon'],
        :id => params['id'],
        :headers => (params['headers'] == 'true'),
        :string_normalizer => Geocollider::StringNormalizer.normalizer_lambda(params['normalize'])
      }
      $stderr.puts csv_options.inspect
      csv_parser = Geocollider::Parsers::CSVParser.new(csv_options)

      pleiades_names, pleiades_places = parse_pleiades(params['normalize'])
      Tempfile.open(['processed_','.csv']) do |output_tempfile|
        CSV.open(output_tempfile, 'wb') do |csv|
          csv_comparison = 
            case params['algorithm']
            when 'place_name'
              csv_parser.comparison_lambda(pleiades_names, pleiades_places, csv, params['distance'].to_f)
            when 'name'
              csv_parser.string_comparison_lambda(pleiades_names, pleiades_places, csv)
            when 'place'
              csv_parser.point_comparison_lambda(pleiades_names, pleiades_places, csv, params['distance'].to_f)
            end
          csv_parser.parse([params['csvfile']], csv_comparison)
        end
        response.headers['Content-Disposition'] = "attachment; filename=geocollider_results-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.csv"
        File.read(output_tempfile.path)
      end
    rescue Exception => e
      if airbrake_enabled?
        csvfile_contents_url = nil
        if File.exist?(params[:csvfile])
          response = RestClient.put "https://transfer.sh/#{URI.escape(File.basename(params[:csvfile]))}", File.new(params[:csvfile],'rb'), :content_type => 'text/csv'
          csvfile_contents_url = response.body
        end
        Airbrake.notify(e, params.merge({
          :csvfile_contents_url => csvfile_contents_url
        }))
        status 500
        @error_message = 'There was an error processing your request. This error has been logged for investigation.'
        haml :error
      else
        raise e
      end
    end
  end

  def openrefine_response(query, limit = nil)
    string_normalizer = Geocollider::StringNormalizer.normalizer_lambda(NORMALIZATION_DEFAULTS)
    pleiades_names, pleiades_places = parse_pleiades(NORMALIZATION_DEFAULTS)
    # normalized_query = string_normalizer.call(query['query'])
    comparison_results = []
    comparison_lambda = nil
    comparison_lambda = Geocollider::Parsers::CSVParser.new({:string_normalizer => string_normalizer}).string_comparison_lambda(pleiades_names, pleiades_places, comparison_results)
    query_point = nil
    if query.has_key?('properties')
      property_pids = query['properties'].map{|p| p['pid']}
      if property_pids.include?(LATITUDE_PID) && property_pids.include?(LONGITUDE_PID)
        comparison_lambda = Geocollider::Parsers::CSVParser.new({:string_normalizer => string_normalizer}).comparison_lambda(pleiades_names, pleiades_places, comparison_results)
        query_point = Geocollider::Point.new(
          latitude: query['properties'].select{|p| p['pid'] == LATITUDE_PID}[0]['v'],
          longitude: query['properties'].select{|p| p['pid'] == LONGITUDE_PID}[0]['v'])
        $stderr.puts "Using Geo: #{query_point.inspect}"
      end
    end
    comparison_lambda.call(query['query'], query_point, nil)
    results_hash = {:result => []}
    if comparison_results.length > 0
      unless limit.nil?
        comparison_results = comparison_results[0..(limit.to_i - 1)]
      end
      comparison_results.each do |comparison_result|
        result_hash = {
          :id => comparison_result[0],
          :name => pleiades_places[comparison_result[0]]['title'],
          :type => [{:id => 'https://pleiades.stoa.org/places/vocab#Place', :name => 'Pleiades Place'}],
          :score => 100.00,
          :match => false
        }
        results_hash[:result] << result_hash
      end
    end
    return results_hash
  end

  route :get, :post, ['/suggest','/suggest/'] do
    $stderr.puts params.inspect
    result_json = nil
    if params.has_key?('prefix')
      result_json = {
        :code => '/api/status/ok',
        :status => '200 OK',
        :prefix => params['prefix'],
        :result => [
          {:id => LATITUDE_PID, :name => 'Latitude'},
          {:id => LONGITUDE_PID, :name => 'Longitude'}
        ]
      }
    end
    if params.has_key?('callback')
      jsonp result_json, params['callback']
    else
      json result_json
    end
  end

  route :get, :post, ['/reconcile','/reconcile/'] do
    $stderr.puts params.inspect
    result_json = nil
    if params.has_key?('query')
      if params['query'] =~ /^{.*}$/
        result_json = openrefine_response(JSON.parse(params['query']),params['limit'])
      else
        result_json = openrefine_response({'query' => params['query']})
      end
    elsif params.has_key?('queries')
      queries = JSON.parse(params['queries'])
      query_responses = {}
      queries.each_key do |query_key|
        query_responses[query_key] = openrefine_response(queries[query_key],params['limit'])
      end
      result_json = query_responses
    else
      result_json = {
        :name => 'Pleiades Reconciliation for OpenRefine',
        :schemaSpace => 'https://pleiades.stoa.org/places/',
        :identifierSpace => 'https://pleiades.stoa.org/places/vocab#',
        :view => {:url => '{{id}}'},
        :suggest => {
            :property => {
              :service_url => request.base_url,
              :service_path => '/suggest'
            }
          },
        :defaultTypes => [{:id => 'Place', :name => 'Pleiades Place'}]
      }
    end
    $stderr.puts result_json.inspect
    if params.has_key?('callback')
      jsonp result_json, params['callback']
    else
      json result_json
    end
  end
end
