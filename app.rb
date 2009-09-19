require 'rubygems'
require 'sinatra'
require 'haml'
require 'actionmailer'

CONFIG = YAML.load(File.read(File.dirname(__FILE__)+'/config.yml'))[Sinatra::Application.environment]
use Rack::Session::Cookie

OID = Rack::Auth::OpenID.new CONFIG[:realm],
  :return_to => CONFIG[:realm]+'/inbox',
  :openid_param => 'credentials'

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def root_url
    request.url.match(/(^.*\/{2}[^\/]*)/)[1]
  end

  def messages to, *new_messages
    $messages ||= {}
    $messages[to] ||= []
    $messages[to] += new_messages
  end
end

get '/' do
  keys = `gpg --list-keys`
  haml :compose, :locals => {:keys => keys.grep(/uid/).map{|s| s.gsub(/uid\s*/, '')}}
end

post '/deliver' do
  to = params['to_'+params[:how]]
  if to.blank? or params[:secrets].blank?
    haml '%h3 Please specify recipient and secrets'
  else
    case params[:how]
    when 'openid'
      to = OpenID.normalize_url to
      messages to, params[:secrets]
      unless params[:notify_openid].blank?
        ApplicationMailer.deliver_fetch_openid(params[:notify_openid], to, root_url+'/login/openid')
      end
      redirect "/success/#{to}"
    when 'gpg'
      io = IO.popen("gpg -er '#{to}'", "r+")
      io.puts params[:secrets]
      io.close_write
      address = to.match(/<(.*)>/)[1] #extract email address
      ApplicationMailer.deliver_secret(to, io)
      io.close_read
      redirect "/success/#{address}"
    else; raise "Unrecognized delivery method: #{params[:how].inspect}"
    end
  end
end

get '/login/openid' do
  haml :"login/openid"
end

post '/login/openid' do
  OID.call env
  redirect "/inbox"
end

get '/inbox' do
  OID.call env
  identifier = session[:openid][:openid_param]
  if identifier
    haml :inbox, :locals => {:messages => messages(identifier, 'hi'), :identifier => identifier}
  else
    redirect "/login/openid"
  end
end

get %r{^/success/(.*)$} do
  to = params[:captures].join
  haml "%h1 Success\n%p Your secrets have been transmitted to #{to.inspect}\n%p\n  %a{:href => '/'} Again"
end

ActionMailer::Base.delivery_method = :sendmail
class ApplicationMailer < ActionMailer::Base
  def secret(to, io)
    recipients      to
    subject         "Secrets"
    from            "secrets@drasticcode.com"
    body            "someone has sent you some secrets"

    attachment "application/pgp-encrypted" do |a|
      a.filename = "secrets.#{Time.now.to_i}.gpg"
      a.body = io.inject{|m,s| m << s}
    end
  end

  def fetch_openid to, openid, login_url
    recipients      to
    subject         "Secretsses"
    from            "secrets@idiosyncra.tc"
    body            "Someone sent you some secrets. Go to #{login_url} and login using your #{openid} OpenId."
  end
end

