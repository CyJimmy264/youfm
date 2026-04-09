# frozen_string_literal: true

config = YouFM::Application.configuration
base_url = ENV.fetch('SPOTIFY_API_BASE_URL', '').strip
config.spotify_api_base_url = base_url unless base_url.empty?

accounts_base_url = ENV.fetch('SPOTIFY_ACCOUNTS_BASE_URL', '').strip
config.spotify_accounts_base_url = accounts_base_url unless accounts_base_url.empty?

token = ENV.fetch('SPOTIFY_ACCESS_TOKEN', '').strip
config.spotify_access_token = token unless token.empty?

client_id = ENV.fetch('SPOTIFY_CLIENT_ID', '').strip
config.spotify_client_id = client_id unless client_id.empty?

redirect_uri = ENV.fetch('SPOTIFY_REDIRECT_URI', '').strip
config.spotify_redirect_uri = redirect_uri unless redirect_uri.empty?

scopes = ENV.fetch('SPOTIFY_SCOPES', '').strip
config.spotify_scopes = scopes.split(/\s+/) unless scopes.empty?
