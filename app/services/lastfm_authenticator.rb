# frozen_string_literal: true

module YouFM
  module Services
    class LastfmAuthenticator
      class Error < StandardError; end
      class CallbackTimeoutError < Error; end

      def initialize(api_key:, secret:, lastfm_client:, token_store:, browser_launcher:, timeout_seconds: 120)
        @api_key = api_key
        @secret = secret
        @lastfm_client = lastfm_client
        @token_store = token_store
        @browser_launcher = browser_launcher
        @timeout_seconds = timeout_seconds
      end

      def configured?
        !api_key.empty? && !secret.empty?
      end

      def connect!
        ensure_configured!

        token_response = lastfm_client.auth_get_token
        request_token = token_response.fetch('token')

        browser_launcher.open(authorization_url(request_token:))

        session_response = poll_for_session!(request_token)
        token_store.save(session_response.fetch('session'))
      end

      def connected?
        !token_store.load.empty?
      end

      def disconnect!
        token_store.clear
      end

      private

      attr_reader :api_key, :secret, :lastfm_client, :token_store, :browser_launcher, :timeout_seconds

      def poll_for_session!(token)
        Timeout.timeout(timeout_seconds) do
          loop do
            sleep 2
            begin
              return lastfm_client.auth_get_session(token)
            rescue LastfmClient::Error => e
              # Error 14 means the user has not authorized the token yet.
              # We can ignore it and continue polling.
              raise unless e.message.include?('"error":14')
            end
          end
        end
      rescue Timeout::Error
        raise CallbackTimeoutError, 'Timed out waiting for Last.fm authorization'
      end

      def authorization_url(request_token:)
        "http://www.last.fm/api/auth/?api_key=#{api_key}&token=#{request_token}"
      end

      def ensure_configured!
        raise Error, 'Set LASTFM_API_KEY and LASTFM_SECRET to use Last.fm OAuth' unless configured?
      end
    end
  end
end
