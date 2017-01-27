require './geocollider-sinatra'

require 'rack/attack'
require 'rack/protection'

use Rack::Attack
use Rack::Protection

run GeocolliderSinatra.new
