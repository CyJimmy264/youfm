# frozen_string_literal: true

require 'time'

module YouFM
  module Services
    class Logger
      class << self
        def info(message, color: nil)
          log(message, stream: $stdout, color: color)
        end

        def warn(message, color: nil)
          log(message, stream: $stderr, color: color)
        end

        private

        def log(message, stream:, color:)
          line = format_line(message)
          stream.puts(color ? format_line(color) : line)
          LogFile.append_async("#{line}\n")
        rescue StandardError
          nil
        end

        def format_line(message)
          "[#{Time.now.iso8601}] #{message}"
        end
      end
    end
  end
end
