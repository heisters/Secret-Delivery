require 'rubygems'
require 'sinatra'
require 'haml'
require 'actionmailer'
gem 'ruby-openid', '>=2.1.2'
require 'openid'
require 'openid/store/filesystem'

logger = Logger.new($stderr)
logger.progname = "OpenID"
OpenID::Util.logger = logger

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
  def openid_consumer
    @openid_consumer ||= OpenID::Consumer.new(
      session,
      OpenID::Store::Filesystem.new("#{File.dirname(__FILE__)}/tmp/openid")
    )
  end

  def root_url
    request.url.match(/(^.*\/{2}[^\/]*)/)[1]
  end

  def messages to, *new_messages
    # normalize
    to = unescape to.to_s
    to = to[0...-1] if to[-1].chr == '/'

    $messages ||= {}
    $messages[to] ||= []
    $messages[to] += new_messages
  end
end

template :layout do
  <<-HAML
!!! Strict
%html{html_attrs('en-en')}
  %head
    %meta{'http-equiv' => "content-type", :content => "text/html; charset=utf-8"}
    %title Secret Delivery
    %style{:type => 'text/css'}
      textarea{width:100%;height:15em;border:solid 1px #666;}
      textarea:focus{background:#ffe;border:solid 1px #666;}
    %script{:type => 'text/javascript', :src => "http://www.google.com/jsapi"}
    %script{:type => 'text/javascript', :src => "/application.js"}
  %body
    #container.container_12
      #header
        %h1 Secret Delivery
      #wrapper
        #flash
        #content= yield
  HAML
end

template :form do
  <<-HAML
%ol
  %li Text is transferred from your browser over an encrypted connection
%form{:method => 'post', :action => '/deliver'}
  %p
    %label{:for => 'how'} Deliver how?
    %select{:id => 'how', :name => 'how'}
      %option{:value => 'openid'} OpenId
      %option{:value => 'gpg'} GPG
    %span.how.openid
      %label{:for => 'to-openid'} Deliver To:
      %input{:type => 'text', :id => 'to-openid', :name => 'to-openid'}
      %label{:for => 'notify-openid'} Notify:
      %input{:type => 'text', :id => 'notify-openid', :name => 'notify-openid'}
    %span.how.gpg
      %label{:for => 'to-gpg'} Deliver To:
      %select{:id => 'to-gpg', :name => 'to-gpg'}
        -keys.unshift('').each do |k|
          %option{:value => k}
            = h k
  %p
    %label{:for => 'secrets'} Secrets:
    %textarea{:name => 'secrets'}
  %p
    %input{:type => 'submit', :value => 'Send Secrets'}
  HAML
end

template :"login/openid" do
  <<-HAML
%form{:method => 'post', :accept_charset => 'UTF-8', :action => '/login/openid'}
  %p
    %label{:for => 'credentials'} Your OpenID:
    %input{:type => 'text', :name => 'credentials', :id => 'credentials'}
    %input{:type => 'submit', :value => 'Login'}
  HAML
end

get '/' do
  keys = `gpg --list-keys`
  haml :form, :locals => {:keys => keys.grep(/uid/).map{|s| s.gsub(/uid\s*/, '')}}
end

post '/deliver' do
  to = params['to-'+params[:how]]
  if to.blank? or params[:secrets].blank?
    haml '%h3 Please specify recipient and secrets'
  else
    messages to, params[:secrets]
    case params[:how]
    when 'openid'
      unless params['notify-openid'].blank?
        ApplicationMailer.deliver_fetch_openid(params['notify-openid'], to, root_url+'/login/openid')
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
  credentials = params[:credentials]
  begin
    request = openid_consumer.begin(credentials)
  rescue OpenID::DiscoveryFailure => why
    "Sorry, we couldn't find your identifier #{credentials.inspect}"
  else
    redirect request.redirect_url(root_url, root_url + "/fetch/openid")
  end
end

get '/fetch/openid' do
  response = openid_consumer.complete params, request.url

  case response.status
    when OpenID::Consumer::FAILURE
      "Sorry, we could not authenticate you with the identifier '{openid}'."
    when OpenID::Consumer::SETUP_NEEDED
      "Immediate request failed - Setup Needed"
    when OpenID::Consumer::CANCEL
      "Login cancelled."
    when OpenID::Consumer::SUCCESS
      haml messages(response.identity_url).map{|m|"%p #{m}"}.join("\n")
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

