require './geocollider-sinatra'

require 'rack/attack'

use Rack::Attack

run GeocolliderSinatra.new
