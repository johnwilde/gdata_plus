require 'oauth'
require 'oauth/request_proxy/typhoeus_request'
require 'typhoeus'

# Methods prefixed with "fetch" indicate that a request is being made to Google.
module GDataPlus
  module Authenticator
    class OAuth
      include Common

      # Create a new instance.
      #
      # === Options
      # [:consumer_key] (required)
      # [:consumer_secret] (required)
      # TODO document optional options
      def initialize(options = {})
        required_options = [:consumer_key, :consumer_secret]
        optional_options = [:request_token, :request_secret, :access_token, :access_secret]
        options = Util.prepare_options(options, required_options, optional_options)

        (required_options + optional_options).each do |option_name|
          instance_variable_set :"@#{option_name}", options[option_name]
        end
      end

      def consumer
        ::OAuth::Consumer.new(@consumer_key, @consumer_secret,
          :request_token_url => "https://www.google.com/accounts/OAuthGetRequestToken",
          :authorize_url => "https://www.google.com/accounts/OAuthAuthorizeToken",
          :access_token_url => "https://www.google.com/accounts/OAuthGetAccessToken"
        )
      end

      # === Arguments
      # [options] (required) see options documentation below
      # [additional_oauth_options]
      #   additional oauth params to pass to
      #   {get_request_token}[http://rdoc.info/github/oauth/oauth-ruby/master/OAuth/Consumer#get_request_token-instance_method];
      #   you will normally leave this blank
      # [additional_request_params]
      #   additional params to pass with request; you will normally leave this blank
      #
      # === Options
      # [:scope]
      #   (required) gdata {scope}[http://code.google.com/apis/gdata/faq.html#AuthScopes]; can be an Array or a String
      # [:oauth_callback]
      #   (required) Google will redirect the user back to this URL after authentication
      def fetch_request_token(options = {}, additional_oauth_options = {}, additional_request_params = {})
        options = ::GDataPlus::Util.prepare_options(options, [:scope, :oauth_callback])

        additional_oauth_options.merge!(:oauth_callback => options[:oauth_callback])

        scope = options[:scope]
        scope = scope.join(" ") if scope.is_a? Array
        additional_request_params.merge!(:scope => scope)

        request_token = consumer.get_request_token(additional_oauth_options, additional_request_params)
        @request_token = request_token.token
        @request_secret = request_token.secret
        request_token
        # TODO deal with error response
      end

      def request_token
        if @request_token && @request_secret
          ::OAuth::RequestToken.new(consumer, @request_token, @request_secret)
        end
      end

      # Exchanges the request token for the access token. The "oauth_verifier" is passed as a
      # URL parameter when Google redirects the client back to your oauth_callback URL.
      def fetch_access_token(oauth_verifier)
        access_token = request_token.get_access_token(:oauth_verifier => oauth_verifier)
        @access_token = access_token.token
        @access_secret = access_token.secret
        @request_token = nil
        @request_secret = nil
        access_token

        # TODO deal with error response
      end

      def access_token
        if @access_token && @access_secret
          ::OAuth::AccessToken.new(consumer, @access_token, @access_secret)
        end
      end

      # Adds authorization header to the specified Typeoeus::Request. The same request is also returned.
      def sign_request!(request)
        # This is a hack so I can use oauth authentication with the 
        # fusion_tables/gdata gem. Decidedly NOT the right way to do this.  
        original_request = nil
        if !request.is_a? ::Typhoeus::Request
          original_request = request
          # Create a temporary request, just to get the authentication header
          request = ::Typhoeus::Request.new(request.url)
        end
        
        helper = ::OAuth::Client::Helper.new(request, {
          :consumer => consumer,
          :request_uri => request.url,
          :token => access_token
        })
        request.headers.merge!({"Authorization" => helper.header})

        if !original_request.nil?
          original_request.headers = request.headers
          return original_request
        end
        return request

      end
    end
  end
end
