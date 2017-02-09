require './geocollider-sinatra'

require 'rack/attack'

use Rack::Attack
require './config/initializers/rack-attack'

run GeocolliderSinatra.new
