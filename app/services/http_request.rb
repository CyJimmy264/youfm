# frozen_string_literal: true

module YouFM
  module Services
    class HttpRequest
      attr_reader :method, :uri, :headers
      attr_accessor :body

      def self.get(uri, headers: {})
        new('GET', uri, headers: headers)
      end

      def self.post(uri, headers: {}, body: nil)
        new('POST', uri, headers: headers, body: body)
      end

      def self.put(uri, headers: {}, body: nil)
        new('PUT', uri, headers: headers, body: body)
      end

      def initialize(method, uri, headers: {}, body: nil)
        @method = method.to_s.upcase
        @uri = uri
        @headers = headers.transform_keys(&:to_s)
        @body = body
      end

      def [](key)
        headers[key.to_s]
      end

      def []=(key, value)
        headers[key.to_s] = value
      end

      def each_header(&)
        headers.each(&)
      end
    end
  end
end
