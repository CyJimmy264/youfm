# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'qt'
require 'securerandom'
require 'socket'
require 'timeout'
require 'time'
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
      YouFM::Services::LogFile.install!
      web_ui_server = YouFM::Application.container.fetch(:web_ui_server)
      web_ui_server.start
      main_window = YouFM::Application.container.fetch(:main_window)
      previous_int = Signal.trap('INT') { main_window.request_shutdown }
      main_window.show
      app.exec
    ensure
      Signal.trap('INT', previous_int) if defined?(previous_int) && previous_int
      web_ui_server&.stop
      app&.dispose
    end
  end
end
