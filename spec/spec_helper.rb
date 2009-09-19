require File.dirname(__FILE__)+'/../app'

require 'rubygems'
require 'spec'
require 'spec/interop/test'
require 'rack/test'

set :environment, :test
Test::Unit::TestCase.send :include, Rack::Test::Methods
Test::Unit::TestCase.send :include, Module.new{def app; Sinatra::Application; end}

Spec::Runner.configure do |config|
  config.before :each do
  end
end
