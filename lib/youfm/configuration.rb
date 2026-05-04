# frozen_string_literal: true

module YouFM
  class Configuration
    attr_accessor :environment, :theme_name, :spotify_api_base_url, :spotify_accounts_base_url,
                  :spotify_access_token, :spotify_client_id, :spotify_redirect_uri, :spotify_scopes,
                  :enable_reloading, :lastfm_api_key, :lastfm_secret

    def initialize(environment: 'development')
      @environment = environment
      @theme_name = 'dark'
      @spotify_api_base_url = 'https://api.spotify.com/v1'
      @spotify_accounts_base_url = 'https://accounts.spotify.com'
      @spotify_access_token = ENV.fetch('SPOTIFY_ACCESS_TOKEN', nil)
      @spotify_client_id = ENV.fetch('SPOTIFY_CLIENT_ID', '39e3731f46c040bbb68cbaa98cb809ef')
      @spotify_redirect_uri = ENV.fetch('SPOTIFY_REDIRECT_URI', 'http://127.0.0.1:8989/callback')
      @spotify_scopes = %w[
        user-read-playback-state
        user-modify-playback-state
        user-read-currently-playing
        playlist-read-private
        playlist-read-collaborative
      ]
      @enable_reloading = environment == 'development'
      @lastfm_api_key = ''
      @lastfm_secret = ''
    end
  end
end
