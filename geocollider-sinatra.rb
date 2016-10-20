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
  File.foreach(params['csvfile']).first(3).join('<br/>')
end
