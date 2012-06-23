require 'omniauth-oauth'

module OmniAuth
  module Strategies
    # Authenticate to Google via OAuth and retrieve basic
    # user information.
    #
    # Usage:
    #    use OmniAuth::Strategies::Google, 'consumerkey', 'consumersecret'
    class Google < OmniAuth::Strategies::OAuth
      def initialize(app, consumer_key=nil, consumer_secret=nil, options={}, &block)
        client_options = {
          :access_token_path => '/accounts/OAuthGetAccessToken',
          :authorize_path => '/accounts/OAuthAuthorizeToken',
          :request_token_path => '/accounts/OAuthGetRequestToken',
          :site => 'https://www.google.com',
        }
        google_user_info_auth = 'https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile'
        options[:scope] ||= google_user_info_auth
        options[:scope] << " #{google_user_info_auth}" unless options[:scope] =~ %r[#{google_user_info_auth}]
        
        options[:client_options] = client_options

        super(app, consumer_key, consumer_secret, options, &block)
      end

      uid do
        user_info['uid']
      end
      
      info do
        user_info
      end
      
      extra do
        { 'user_hash' => user_hash }
      end

      def user_info
        email = user_hash['email']
        id = user_hash['id']
        
        if name.strip == '(unknown)'
          name = email
        else
          name = user_hash['name']
        end

        {
          'email' => email,
          'uid' => id,
          'name' => name,
        }
      end

      def user_hash
        @user_hash ||= MultiJson.decode(@access_token.get('https://www.googleapis.com/oauth2/v1/userinfo?alt=json').body)
      end

      # Monkeypatch OmniAuth to pass the scope and authorize_params in the consumer.get_request_token call
      def request_phase
        request_options = {:scope => options[:scope]}
        request_options.merge!(options[:authorize_params])
      
        request_token = consumer.get_request_token({:oauth_callback => callback_url}, request_options)
        session['oauth'] ||= {}
        session['oauth'][name.to_s] = {'callback_confirmed' => request_token.callback_confirmed?, 'request_token' => request_token.token, 'request_secret' => request_token.secret}
        r = Rack::Response.new
      
        if request_token.callback_confirmed?
          r.redirect(request_token.authorize_url)
        else
          r.redirect(request_token.authorize_url(:oauth_callback => callback_url))
        end
      
        r.finish
      
        rescue ::Timeout::Error => e
          fail!(:timeout, e)
        rescue ::Net::HTTPFatalError, ::OpenSSL::SSL::SSLError => e
          fail!(:service_unavailable, e)
      end
    end
  end
end
