# frozen_string_literal: true

require 'rbconfig'

module YouFM
  module Services
    class BrowserLauncher
      def open(url)
        command = launcher_command
        return false unless command

        system(command, url)
      end

      private

      def launcher_command
        host_os = RbConfig::CONFIG['host_os']
        return 'open' if host_os.include?('darwin')
        return 'xdg-open' if host_os.include?('linux')

        nil
      end
    end
  end
end
