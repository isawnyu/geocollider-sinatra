ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require_relative '../geocollider-sinatra.rb'

class GeocolliderSinatraTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def app
    GeocolliderSinatra
  end

  def test_landing
    get '/'
    assert last_response.ok?
  end
end
