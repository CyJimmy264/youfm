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
      register(:spotify_token_store) { Services::SpotifyTokenStore.new }
      register(:spotify_playlist_cache) { Services::SpotifyPlaylistCache.new }
      register(:browser_launcher) { Services::BrowserLauncher.new }
      register(:spotify_authenticator) do
        Services::SpotifyAuthenticator.new(
          client_id: config.spotify_client_id,
          redirect_uri: config.spotify_redirect_uri,
          scopes: config.spotify_scopes,
          accounts_base_url: config.spotify_accounts_base_url,
          token_store: fetch(:spotify_token_store),
          browser_launcher: fetch(:browser_launcher)
        )
      end
      register(:spotify_client) do
        Services::SpotifyClient.new(
          access_token: config.spotify_access_token,
          base_url: config.spotify_api_base_url,
          token_store: fetch(:spotify_token_store),
          authenticator: fetch(:spotify_authenticator),
          playlist_cache: fetch(:spotify_playlist_cache)
        )
      end
      register(:music_source) do
        Services::MusicSources::SpotifySource.new(client: fetch(:spotify_client))
      end
      register(:lastfm_token_store) { Services::LastfmTokenStore.new }
      register(:lastfm_similar_artists_cache) { Services::LastfmSimilarArtistsCache.new }
      register(:lastfm_client) do
        session_data = fetch(:lastfm_token_store).load
        Services::LastfmClient.new(
          api_key: config.lastfm_api_key,
          secret: config.lastfm_secret,
          session_key: session_data['key'],
          similar_artists_cache: fetch(:lastfm_similar_artists_cache)
        )
      end
      register(:lastfm_authenticator) do
        Services::LastfmAuthenticator.new(
          api_key: config.lastfm_api_key,
          secret: config.lastfm_secret,
          lastfm_client: fetch(:lastfm_client),
          token_store: fetch(:lastfm_token_store),
          browser_launcher: fetch(:browser_launcher)
        )
      end
      register(:recommendation_generator) do
        Services::RecommendationGenerator.new(
          lastfm_client: fetch(:lastfm_client),
          spotify_client: fetch(:spotify_client)
        )
      end
      register(:main_view_model) do
        ViewModels::MainViewModel.new(
          source: fetch(:music_source),
          recommendation_generator: fetch(:recommendation_generator),
          lastfm_authenticator: fetch(:lastfm_authenticator)
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
