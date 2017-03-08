#!/usr/bin/env ruby

require 'sinatra/base'
require 'tempfile'
require 'haml'
require 'geocollider'

# JS/CSS asset management
require 'sprockets'
require 'uglifier'
require 'sass'
require 'coffee-script'
require 'execjs'

class GeocolliderSinatra < Sinatra::Base
  pleiades = Geocollider::PleiadesParser.new()

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

  get '/' do
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
    @uploaded_filename = tempfile_file.path
    $stderr.puts @uploaded_filename
    File.open(@uploaded_filename, "w") do |f|
      f.write(params['csvfile'][:tempfile].read)
    end

    @csv_preview = File.foreach(@uploaded_filename).first(3).join("\n").squeeze("\n")
    haml :post_upload
  end

  post '/process' do
    $stderr.puts params.inspect
    csv_options = {
      :separator => params['separator'] == 'tab' ? "\t" : ',',
      :quote_char => params['quote_char'].empty? ? "\u{FFFF}" : params['quote_char'],
      :names => params['names'].split(','),
      :lat => params['lat'],
      :lon => params['lon'],
      :id => params['id'],
      :headers => (params['headers'] == 'true')
    }
    $stderr.puts csv_options.inspect
    csv_parser = Geocollider::CSVParser.new(csv_options)

    pleiades_names, pleiades_places = pleiades.parse(Geocollider::PleiadesParser::FILENAMES)
    Tempfile.open(['processed_','.csv']) do |output_tempfile|
      CSV.open(output_tempfile, 'wb') do |csv|
        csv_comparison = csv_parser.comparison_lambda(pleiades_names, pleiades_places, csv)
        if(params['algorithm'] == 'name')
          csv_comparison = csv_parser.string_comparison_lambda(pleiades_names, pleiades_places, csv)
        end
        csv_parser.parse([params['csvfile']], csv_comparison)
      end
      response.headers['Content-Disposition'] = "attachment; filename=geocollider_results-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.csv"
      File.read(output_tempfile.path)
    end
  end
end
