# frozen_string_literal: true

YouFM::Application.configure do |config|
  config.enable_reloading = ENV.fetch('YOUFM_RELOAD', '0') == '1'
end
