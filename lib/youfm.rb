# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'qt'
require 'uri'
require 'yaml'
require 'zeitwerk'

require_relative 'youfm/version'
require_relative 'youfm/configuration'
require_relative 'youfm/container'
require_relative '../config/application'

module YouFM
  class CLI
    def self.start(_argv = [])
      app = YouFM::Application.boot!
      main_window = YouFM::Application.container.fetch(:main_window)
      previous_int = Signal.trap('INT') { main_window.request_shutdown }
      main_window.show
      app.exec
    ensure
      Signal.trap('INT', previous_int) if defined?(previous_int) && previous_int
      app&.dispose
    end
  end
end
