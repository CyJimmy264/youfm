# frozen_string_literal: true

require 'net/http'

module YouFM
  module Services
    class PersistentHttpClient
      def initialize(open_timeout:, read_timeout:)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @sessions = {}
        @mutex = Mutex.new
      end

      def request(request)
        with_session(request.uri) { |http| http.request(request) }
      rescue IOError, Errno::ECONNRESET, Errno::EPIPE
        reset_session(request.uri)
        with_session(request.uri) { |http| http.request(request) }
      end

      private

      attr_reader :open_timeout, :read_timeout, :sessions, :mutex

      def with_session(uri)
        mutex.synchronize do
          yield(session_for(uri))
        end
      end

      def session_for(uri)
        key = session_key(uri)
        session = sessions[key]
        return session if reusable_session?(session)

        sessions[key] = start_session(uri)
      end

      def reusable_session?(session)
        return false unless session
        return true unless session.respond_to?(:started?)

        session.started?
      end

      def start_session(uri)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: open_timeout,
          read_timeout: read_timeout
        )
      end

      def reset_session(uri)
        mutex.synchronize do
          session = sessions.delete(session_key(uri))
          session&.finish if session.respond_to?(:started?) && session.started?
        rescue IOError
          nil
        end
      end

      def session_key(uri)
        [uri.scheme, uri.host, uri.port]
      end
    end
  end
end
