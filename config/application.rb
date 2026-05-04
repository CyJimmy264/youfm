# frozen_string_literal: true

module YouFM
  module Application
    module_function

    def boot!
      setup_qt
      loader.setup
      load_environment!
      load_initializers!
      load_persisted_configuration!
      qt_app
    end

    def root
      @root ||= File.expand_path('..', __dir__)
    end

    def environment
      ENV.fetch('YOUFM_ENV', 'development')
    end

    def configuration
      @configuration ||= Configuration.new(environment: environment)
    end

    def configure
      yield(configuration)
    end

    def container
      @container ||= Container.new(config: configuration)
    end

    def loader
      @loader ||= Zeitwerk::Loader.new.tap do |autoload|
        autoload.push_dir(File.join(root, 'app'), namespace: YouFM)
        autoload.enable_reloading if configuration.enable_reloading
      end
    end

    def setup_qt
      return if @qt_app

      @qt_app = QApplication.new(0, [])
      apply_qt_identity!
    rescue StandardError
      @qt_app ||= nil
    end

    def qt_app
      @qt_app
    end

    def load_environment!
      path = File.join(root, 'config', 'environments', "#{environment}.rb")
      require path if File.exist?(path)
    end

    def load_initializers!
      Dir[File.join(root, 'config', 'initializers', '*.rb')].each { |file| require file }
    end

    def load_persisted_configuration!
      return if ENV.fetch('YOUFM_THEME', '').strip != ''

      persisted_theme = Services::SettingsStore.new.read_theme_name
      configuration.theme_name = persisted_theme if persisted_theme
    end

    def apply_qt_identity!
      QApplication.set_application_name('youfm')
      QApplication.set_application_display_name('YouFM')
      QApplication.set_organization_name('mveynberg')
    end
  end
end
