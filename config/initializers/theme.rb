# frozen_string_literal: true

theme_name = ENV.fetch('YOUFM_THEME', '').strip
YouFM::Application.configuration.theme_name = theme_name unless theme_name.empty?
