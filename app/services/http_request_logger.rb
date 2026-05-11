# frozen_string_literal: true

require 'uri'

module YouFM
  module Services
    class HttpRequestLogger
      RESET = "\e[0m"
      COLORS = {
        spotify: "\e[32m",
        lastfm: "\e[35m",
        method: "\e[36m",
        ok: "\e[32m",
        error: "\e[31m",
        elapsed: "\e[33m"
      }.freeze
      SENSITIVE_PARAMS = %w[api_key api_sig sk token].freeze

      class << self
        def log(provider:, method:, uri:, status:, elapsed_ms:)
          message = formatted(provider:, method:, uri:, status:, elapsed_ms:)
          Logger.info(
            message,
            color: formatted(provider:, method:, uri:, status:, elapsed_ms:, color: true)
          )
        end

        def elapsed_ms_since(started_at)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        private

        def formatted(provider:, method:, uri:, status:, elapsed_ms:, color: false)
          provider_label = provider_label(provider, color:)
          method_label = method_label(method, color:)
          status_label = status_label(status, color:)
          elapsed_label = elapsed_label(elapsed_ms, color:)
          format(
            '[youfm] http %<provider>-16s %<method>-15s %<status>-12s %<elapsed>-17s %<url>s',
            provider: provider_label,
            method: method_label,
            status: status_label,
            elapsed: elapsed_label,
            url: redacted_url(uri)
          )
        end

        def provider_label(provider, color:)
          label = provider.to_s.upcase.ljust(7)
          color ? colorize(label, COLORS.fetch(provider, COLORS[:method])) : label
        end

        def method_label(method, color:)
          label = method.to_s.upcase.ljust(6)
          color ? colorize(label, COLORS[:method]) : label
        end

        def status_label(status, color:)
          label = status.to_s.rjust(4)
          return label unless color

          colorize(label, status.to_i.between?(200, 399) ? COLORS[:ok] : COLORS[:error])
        end

        def elapsed_label(elapsed_ms, color:)
          label = "#{elapsed_ms}ms".rjust(7)
          color ? colorize(label, COLORS[:elapsed]) : label
        end

        def colorize(value, color)
          "#{color}#{value}#{RESET}"
        end

        def redacted_url(uri)
          parsed_uri = URI(uri.to_s)
          return parsed_uri.to_s if parsed_uri.query.to_s.empty?

          parsed_uri.query = URI.encode_www_form(redacted_query_params(parsed_uri))
          parsed_uri.to_s
        rescue URI::InvalidURIError
          uri.to_s
        end

        def redacted_query_params(uri)
          URI.decode_www_form(uri.query).map do |key, value|
            SENSITIVE_PARAMS.include?(key) ? [key, '[REDACTED]'] : [key, value]
          end
        end
      end
    end
  end
end
