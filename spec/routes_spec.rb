require File.dirname(__FILE__)+'/spec_helper'

describe 'routes' do
  describe "get '/'" do
    def do_get options={}
      get '/', {}.merge(options)
    end

    it "should respond ok" do
      do_get
      last_response.should be_ok
    end

    it "should render the compose form" do
      do_get
      last_response.body.should include('Text is transferred from your browser over an encrypted connection')
    end
  end

  describe "post '/deliver'" do
    before :each do
      @io = StringIO.new
      IO.stub!(:popen).and_return(@io)
      ApplicationMailer.stub!(:deliver_secret)
    end

    describe "to gpg" do
      def do_post options={}
        post '/deliver', {
          :how => 'gpg',
          :to_gpg => '"John Doe" <j@example.com>',
          :secrets => 'secret content'
        }.merge(options)
      end

      it "should redirect to success" do
        do_post
        last_response.should be_redirect
        last_response.location.should == "/success/j@example.com"
      end

      it "should deliver a secret email" do
        ApplicationMailer.should_receive(:deliver_secret)
        do_post
      end
    end

    describe "to openid" do
      def do_post options={}
        post '/deliver', {
          :how => 'openid',
          :to_openid => 'http://example.com/j',
          :notify_openid => 'j@example.com',
          :secrets => 'secret content'
        }.merge(options)
      end

      it "should redirect to success" do
        do_post
        last_response.should be_redirect
        last_response.location.should == "/success/http://example.com/j"
      end

      it "should deliver a fetch email" do
        ApplicationMailer.should_receive(:deliver_fetch_openid)
        do_post
      end
    end
  end

  describe "get '/login/openid'" do
    def do_get options={}
      get '/login/openid', {}.merge(options)
    end

    it "should respond ok" do
      do_get
      last_response.should be_ok
    end

    it "should render the openid login form" do
      do_get
      last_response.body.should include('Your OpenID')
    end
  end

  describe "post '/login/openid'" do
    def do_post options={}
      post '/login/openid', {:credentials => "http://example.com/j"}.merge(options)
    end

    it "should redirect to openid fetch on success"
  end
end
