# frozen_string_literal: true

require 'httpx'

module YouFM
  module Services
    class PersistentHttpClient
      MAX_ATTEMPTS = 3

      Response = Struct.new(:status, :headers, :body) do
        def code
          status.to_s
        end

        def [](key)
          headers[key] || headers[key.to_s.downcase]
        end
      end

      def initialize(open_timeout:, read_timeout:)
        @session = HTTPX.plugin(:persistent).with(
          timeout: {
            connect_timeout: open_timeout,
            operation_timeout: read_timeout
          }
        )
      end

      def request(request)
        attempt = 0

        begin
          attempt += 1
          perform_request(request)
        rescue HTTPX::TimeoutError, HTTPX::ConnectionError => e
          retry if retry_request?(request, e, attempt)

          raise
        rescue NoMethodError => e
          raise unless nil_multiplication_error?(e)

          retry if retry_request?(request, e, attempt)

          raise HTTPX::ConnectionError, e.message
        end
      end

      private

      attr_reader :session

      def perform_request(request)
        response = session.request(
          request.method,
          request.uri,
          headers: request_headers(request),
          body: request.body
        )
        raise response.error if response.is_a?(HTTPX::ErrorResponse)

        Response.new(response.status, response.headers, response.body.to_s)
      end

      def retry_request?(request, error, attempt)
        return false if attempt >= MAX_ATTEMPTS

        Services::Logger.warn(
          "[youfm] http retrying: method=#{request.method} url=#{request.uri} " \
          "error=#{error.class}: #{error.message} attempt=#{attempt + 1}/#{MAX_ATTEMPTS}"
        )
        true
      end

      def nil_multiplication_error?(error)
        error.name == :* && error.receiver.nil?
      end

      def request_headers(request)
        request.headers
      end
    end
  end
end
