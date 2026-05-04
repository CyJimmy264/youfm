# frozen_string_literal: true

require 'digest'
require 'rbconfig'

module YouFM
  module Services
    class SpotifyAuthenticator
      class Error < StandardError; end
      class CallbackTimeoutError < Error; end

      SUCCESS_RESPONSE = <<~HTML
        HTTP/1.1 200 OK
        Content-Type: text/html; charset=utf-8
        Connection: close

        <html>
          <body style="font-family: sans-serif; padding: 24px;">
            <h1>YouFM</h1>
            <p>Spotify authorization completed. You can close this tab and return to the app.</p>
          </body>
        </html>
      HTML

      FAILURE_RESPONSE = <<~HTML
        HTTP/1.1 400 Bad Request
        Content-Type: text/html; charset=utf-8
        Connection: close

        <html>
          <body style="font-family: sans-serif; padding: 24px;">
            <h1>YouFM</h1>
            <p>Spotify authorization failed. Return to the app for details.</p>
          </body>
        </html>
      HTML

      def initialize(client_id:, redirect_uri:, scopes:, accounts_base_url:, token_store:, browser_launcher:,
                     timeout_seconds: 120)
        @client_id = client_id.to_s.strip
        @redirect_uri = redirect_uri.to_s.strip
        @scopes = Array(scopes)
        @accounts_base_url = accounts_base_url
        @token_store = token_store
        @browser_launcher = browser_launcher
        @timeout_seconds = timeout_seconds
      end

      def configured?
        !client_id.empty? && !redirect_uri.empty?
      end

      def connect!
        ensure_configured!

        state = SecureRandom.hex(24)
        verifier = generate_code_verifier
        callback = capture_callback!(state:, verifier:)
        exchange_code!(
          code: callback.fetch(:code),
          verifier: verifier
        )
      end

      def refresh!(refresh_token)
        ensure_configured!
        payload = post_token(
          grant_type: 'refresh_token',
          refresh_token: refresh_token,
          client_id: client_id
        )
        merged = token_store.load.merge(payload)
        merged['refresh_token'] ||= refresh_token
        token_store.save(with_expiration(merged))
        token_store.load
      end

      private

      attr_reader :client_id, :redirect_uri, :scopes, :accounts_base_url, :token_store, :browser_launcher,
                  :timeout_seconds

      def capture_callback!(state:, verifier:)
        redirect = URI.parse(redirect_uri)
        server = TCPServer.new(redirect.host, redirect.port)
        browser_launcher.open(authorization_url(state:, verifier:))

        Timeout.timeout(timeout_seconds) do
          loop do
            socket = server.accept
            result = read_callback_request(socket, redirect.path, state)
            next unless result

            return result
          ensure
            socket&.close
          end
        end
      rescue Timeout::Error
        raise CallbackTimeoutError, 'Timed out waiting for Spotify authorization callback'
      ensure
        server&.close
      end

      def read_callback_request(socket, expected_path, expected_state)
        request_line = socket.gets.to_s
        return nil if request_line.empty?

        _method, target, = request_line.split
        consume_headers(socket)
        uri = URI.parse(target)

        unless uri.path == expected_path
          socket.write(FAILURE_RESPONSE)
          return nil
        end

        params = URI.decode_www_form(uri.query.to_s).to_h
        if params['state'] != expected_state || params['error']
          socket.write(FAILURE_RESPONSE)
          raise Error, params['error'] || 'Spotify authorization state mismatch'
        end

        socket.write(SUCCESS_RESPONSE)
        { code: params.fetch('code') }
      end

      def consume_headers(socket)
        loop do
          line = socket.gets
          break if line.nil? || line == "\r\n"
        end
      end

      def authorization_url(state:, verifier:)
        challenge = base64_urlsafe(Digest::SHA256.digest(verifier))
        uri = URI.join(accounts_base_url.end_with?('/') ? accounts_base_url : "#{accounts_base_url}/", 'authorize')
        uri.query = URI.encode_www_form(
          client_id: client_id,
          response_type: 'code',
          redirect_uri: redirect_uri,
          code_challenge_method: 'S256',
          code_challenge: challenge,
          state: state,
          scope: scopes.join(' ')
        )
        uri.to_s
      end

      def exchange_code!(code:, verifier:)
        payload = post_token(
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        )
        token_store.save(with_expiration(payload))
        token_store.load
      end

      def post_token(params)
        uri = URI.join(accounts_base_url.end_with?('/') ? accounts_base_url : "#{accounts_base_url}/", 'api/token')
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request.body = URI.encode_www_form(params)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        raise Error, response.body.to_s if response.code.to_i >= 400

        JSON.parse(response.body)
      end

      def with_expiration(payload)
        expires_in = payload['expires_in'].to_i
        return payload unless expires_in.positive?

        payload.merge('expires_at' => (Time.now + expires_in).utc.iso8601)
      end

      def generate_code_verifier
        base64_urlsafe(SecureRandom.random_bytes(64))
      end

      def base64_urlsafe(bytes)
        [bytes].pack('m0').tr('+/', '-_').delete('=')
      end

      def ensure_configured!
        raise Error, 'Set SPOTIFY_CLIENT_ID and SPOTIFY_REDIRECT_URI to use Spotify OAuth' unless configured?
      end
    end
  end
end
