# frozen_string_literal: true

require_relative '../../lib/youfm/configuration'

YouFM::Application.configure do |config|
  api_key = ENV.fetch('LASTFM_API_KEY', '').strip
  secret = ENV.fetch('LASTFM_SECRET', '').strip

  config.lastfm_api_key = api_key unless api_key.empty?
  config.lastfm_secret = secret unless secret.empty?
end
