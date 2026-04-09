# frozen_string_literal: true

module YouFM
  class Configuration
    attr_accessor :environment, :theme_name, :spotify_api_base_url, :spotify_access_token, :enable_reloading

    def initialize(environment: 'development')
      @environment = environment
      @theme_name = 'dark'
      @spotify_api_base_url = 'https://api.spotify.com/v1'
      @spotify_access_token = ENV['SPOTIFY_ACCESS_TOKEN']
      @enable_reloading = environment == 'development'
    end
  end
end
