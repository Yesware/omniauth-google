require 'omniauth-oauth'

module OmniAuth
  module Strategies
    # Authenticate to Google via OAuth and retrieve basic
    # user information.
    #
    # Usage:
    #    use OmniAuth::Strategies::Google, 'consumerkey', 'consumersecret'
    class Google < OmniAuth::Strategies::OAuth
      option :client_options, {
        :access_token_path => '/accounts/OAuthGetAccessToken',
        :authorize_path => '/accounts/OAuthAuthorizeToken',
        :request_token_path => '/accounts/OAuthGetRequestToken',
        :site => 'https://www.google.com'
      }

      option :scope, "https://www.google.com/m8/feeds"

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
        email = user_hash['feed']['id']['$t']

        name = user_hash['feed']['author'].first['name']['$t']
        name = email if name.strip == '(unknown)'

        {
          'email' => email,
          'uid' => email,
          'name' => name,
        }
      end

      def user_hash
        # Google is very strict about keeping authorization and
        # authentication separated.
        # They give no endpoint to get a user's profile directly that I can
        # find. We *can* get their name and email out of the contacts feed,
        # however. It will fail in the extremely rare case of a user who has
        # a Google Account but has never even signed up for Gmail. This has
        # not been seen in the field.
        @user_hash ||= MultiJson.decode(@access_token.get('https://www.google.com/m8/feeds/contacts/default/full?max-results=1&alt=json').body)
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
