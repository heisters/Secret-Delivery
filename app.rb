require 'rubygems'
require 'sinatra'
require 'haml'
require 'actionmailer'
require 'pstore'

CONFIG = YAML.load(File.read(File.dirname(__FILE__)+'/config.yml'))[Sinatra::Application.environment]
use Rack::Session::Cookie

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def root_url
    request.url.match(/(^.*\/{2}[^\/]*)/)[1]
  end

  def oid
    @oid ||= Rack::Auth::OpenID.new CONFIG[:realm],
      :return_to => CONFIG[:realm]+'/inbox',
      :openid_param => 'credentials'
  end

  def db
    @db ||= PStore.new File.dirname(__FILE__)+'/db.pstore'
  end

  def messages to, *new_messages
    db.transaction do
      db[to] ||= []
      db[to] += new_messages
    end
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
      oid # ensure that OpenID has been initialized
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
  oid.call env
  redirect "/inbox"
end

get '/inbox' do
  oid.call env
  identifier = session[:openid][:openid_param]
  if identifier
    identifier = OpenID.normalize_url identifier
    haml :inbox, :locals => {:messages => messages(identifier), :identifier => identifier}
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

