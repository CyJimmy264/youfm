# frozen_string_literal: true

module YouFM
  class Container
    def initialize(config:)
      @config = config
      @providers = {}
      @memoized = {}
      register_defaults
    end

    def register(key, &provider)
      providers[key.to_sym] = provider
    end

    def fetch(key)
      name = key.to_sym
      return memoized[name] if memoized.key?(name)

      memoized[name] = providers.fetch(name).call
    end

    private

    attr_reader :config, :providers, :memoized

    def register_defaults
      register(:theme) { Styles::Theme.new(name: config.theme_name) }
      register(:settings_store) { Services::SettingsStore.new }
      register(:spotify_client) do
        Services::SpotifyClient.new(
          access_token: config.spotify_access_token,
          base_url: config.spotify_api_base_url
        )
      end
      register(:music_source) do
        Services::MusicSources::SpotifySource.new(client: fetch(:spotify_client))
      end
      register(:main_view_model) do
        ViewModels::MainViewModel.new(
          source: fetch(:music_source)
        )
      end
      register(:main_window) do
        Views::MainWindow.new(
          view_model: fetch(:main_view_model),
          theme: fetch(:theme),
          settings_store: fetch(:settings_store)
        )
      end
    end
  end
end
