# frozen_string_literal: true

require_relative '../../lib/youfm/configuration'

YouFM::Application.configure do |config|
  config.lastfm_api_key = ENV.fetch('LASTFM_API_KEY', '80372e9e7a406d2e637edc0532c44635')
  config.lastfm_secret = ENV.fetch('LASTFM_SECRET', 'c1a71ee9cca8e385034bcd5d3acf11fc')
end
