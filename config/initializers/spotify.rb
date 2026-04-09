# frozen_string_literal: true

config = YouFM::Application.configuration
base_url = ENV.fetch('SPOTIFY_API_BASE_URL', '').strip
config.spotify_api_base_url = base_url unless base_url.empty?

token = ENV.fetch('SPOTIFY_ACCESS_TOKEN', '').strip
config.spotify_access_token = token unless token.empty?
