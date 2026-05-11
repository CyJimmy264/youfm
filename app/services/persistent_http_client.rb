# frozen_string_literal: true

require 'httpx'

module YouFM
  module Services
    class PersistentHttpClient
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
        response = session.request(
          request.method,
          request.uri,
          headers: request_headers(request),
          body: request.body
        )
        raise response.error if response.is_a?(HTTPX::ErrorResponse)

        Response.new(response.status, response.headers, response.body.to_s)
      end

      private

      attr_reader :session

      def request_headers(request)
        request.headers
      end
    end
  end
end
