require 'rubygems'
require 'sinatra'

set :run, false
set :environment, ENV['RACK_ENV']

# Allow stuff to log to STDOUT/ERR, eg. OpenID
FileUtils.mkdir_p 'log' unless File.exists?('log')
log = File.new("log/sinatra.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

require 'app'
run Sinatra::Application
