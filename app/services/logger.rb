# frozen_string_literal: true

require 'time'

module YouFM
  module Services
    class Logger
      class << self
        def info(message)
          log(message, stream: $stdout)
        end

        def warn(message)
          log(message, stream: $stderr)
        end

        private

        def log(message, stream:)
          line = format_line(message)
          stream.puts(line)
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
