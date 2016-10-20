#!/usr/bin/env ruby

require 'sinatra'
require 'tempfile'
require 'haml'
require 'geocollider'

pleiades = Geocollider::PleiadesParser.new()
pleiades_names, pleiades_places = pleiades.parse(pleiades.download())

get '/' do
  'Hello world'
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

  @csv_preview = File.foreach(@uploaded_filename).first(3).join('<br/>')
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
    :id => params['id']
  }
  $stderr.puts csv_options.inspect
  csv_parser = Geocollider::CSVParser.new(csv_options)
  output_tempfile = Tempfile.new(['processed_','.csv'])
  output_tempfile.close
  output_csv = output_tempfile.path
  CSV.open(output_csv, 'wb') do |csv|
    csv_comparison = csv_parser.comparison_lambda(pleiades_names, pleiades_places, csv)
    csv_parser.parse([params['csvfile']], csv_comparison)
  end
  response.headers['Content-Disposition'] = "attachment; filename=geocollider_results-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.csv"
  File.read(output_csv)
end
