require 'spec_helper'

RSpec.configure do |config|
  config.include WebMock::API
  config.include Rack::Test::Methods
  config.extend  OmniAuth::Test::StrategyMacros, :type => :strategy
end

describe "OmniAuth::Strategies::Google" do

  def app
    Rack::Builder.new {
      use OmniAuth::Test::PhonySession
      use OmniAuth::Builder do
        provider :google
      end
      run lambda { |env| [404, {'Content-Type' => 'text/plain'}, [env.key?('omniauth.auth').to_s]] }
    }.to_app
  end

  def session
    last_request.env['rack.session']
  end

  before do
    stub_request(:post, 'https://www.google.com/accounts/OAuthGetRequestToken').
      to_return(:body => "oauth_token=yourtoken&oauth_token_secret=yoursecret&oauth_callback_confirmed=true")
  end

  describe '/auth/google' do
    context 'successful' do
      before do
        get '/auth/google'
      end

      it 'should redirect to authorize_url' do
        last_response.should be_redirect
        last_response.headers['Location'].should == 'https://www.google.com/accounts/OAuthAuthorizeToken?oauth_token=yourtoken'
      end

      # it 'should redirect to authorize_url with authorize_params when set' do
      #   # get '/auth/example.org_with_authorize_params'
      #   get '/auth/google_with_authorize_params'
      #   last_response.should be_redirect
      #   [
      #     'https://api.example.org/oauth/authorize?abc=def&oauth_token=yourtoken',
      #     'https://api.example.org/oauth/authorize?oauth_token=yourtoken&abc=def'
      #   ].should be_include(last_response.headers['Location'])
      # end

      it 'should set appropriate session variables' do
        session['oauth'].should == {"google" => {'callback_confirmed' => true, 'request_token' => 'yourtoken', 'request_secret' => 'yoursecret'}}
      end
    end

    context 'unsuccessful' do
      before do
        stub_request(:post, 'https://www.google.com/accounts/OAuthGetRequestToken').
           to_raise(::Net::HTTPFatalError.new(%Q{502 "Bad Gateway"}, nil))
        get '/auth/google'
      end

      it 'should call fail! with :service_unavailable' do
        last_request.env['omniauth.error'].should be_kind_of(::Net::HTTPFatalError)
        last_request.env['omniauth.error.type'] = :service_unavailable
      end

      context "SSL failure" do
        before do
          stub_request(:post, 'https://www.google.com/accounts/OAuthGetRequestToken').
             to_raise(::OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=SSLv3 read server certificate B: certificate verify failed"))
          get '/auth/google'
        end

        it 'should call fail! with :service_unavailable' do
          last_request.env['omniauth.error'].should be_kind_of(::OpenSSL::SSL::SSLError)
          last_request.env['omniauth.error.type'] = :service_unavailable
        end
      end
    end
  end

  describe '/auth/google/callback' do
    before do
      body =<<BODY
        {
          "feed" : {
            "id" : {
              "$t" : "http://www.google.com/m8/feeds/contacts/dudeman%example.com/base/6d45af48e519ef7" 
            },
            "author" :  [
              {
                "name" : {"$t" : "Dude Man"}
              }
            ]
          }
        }
BODY

      stub_request(:post, 'https://www.google.com/accounts/OAuthGetAccessToken').
        to_return(:body => "oauth_token=yourtoken&oauth_token_secret=yoursecret")
      stub_request(:get, "https://www.google.com/m8/feeds/contacts/default/full?alt=json&max-results=1").
        to_return(:status => 200, :body => body, :headers => {})
      get '/auth/google/callback', {:oauth_verifier => 'dudeman'}, {'rack.session' => {'oauth' => {"google" => {'callback_confirmed' => true, 'request_token' => 'yourtoken', 'request_secret' => 'yoursecret'}}}}
    end

    it 'should exchange the request token for an access token' do
      last_request.env['omniauth.auth']['provider'].should == 'google'
      last_request.env['omniauth.auth']['extra']['access_token'].should be_kind_of(OAuth::AccessToken)
    end

    it 'should call through to the master app' do
      last_response.body.should == 'true'
    end

    context "bad gateway (or any 5xx) for access_token" do
      before do
        stub_request(:post, 'https://www.google.com/accounts/OAuthGetAccessToken').
           to_raise(::Net::HTTPFatalError.new(%Q{502 "Bad Gateway"}, nil))
        get '/auth/google/callback', {:oauth_verifier => 'dudeman'}, {'rack.session' => {'oauth' => {"google" => {'callback_confirmed' => true, 'request_token' => 'yourtoken', 'request_secret' => 'yoursecret'}}}}
      end

      it 'should call fail! with :service_unavailable' do
        last_request.env['omniauth.error'].should be_kind_of(::Net::HTTPFatalError)
        last_request.env['omniauth.error.type'] = :service_unavailable
      end
    end

    context "SSL failure" do
      before do
        stub_request(:post, 'https://www.google.com/accounts/OAuthGetAccessToken').
           to_raise(::OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=SSLv3 read server certificate B: certificate verify failed"))
        get '/auth/google/callback', {:oauth_verifier => 'dudeman'}, {'rack.session' => {'oauth' => {"google" => {'callback_confirmed' => true, 'request_token' => 'yourtoken', 'request_secret' => 'yoursecret'}}}}
      end

      it 'should call fail! with :service_unavailable' do
        last_request.env['omniauth.error'].should be_kind_of(::OpenSSL::SSL::SSLError)
        last_request.env['omniauth.error.type'] = :service_unavailable
      end
    end
  end

  describe '/auth/google/callback with expired session' do
    before do
      stub_request(:post, 'https://www.google.com/accounts/OAuthGetAccessToken').
         to_return(:body => "oauth_token=yourtoken&oauth_token_secret=yoursecret")
      get '/auth/google/callback', {:oauth_verifier => 'dudeman'}, {'rack.session' => {}}
    end

    it 'should call fail! with :session_expired' do
      last_request.env['omniauth.error'].should be_kind_of(::OmniAuth::NoSessionError)
      last_request.env['omniauth.error.type'] = :session_expired
    end
  end
end
