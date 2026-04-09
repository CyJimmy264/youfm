# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Container do
  let(:config) do
    instance_double(
      YouFM::Configuration,
      theme_name: 'dark',
      spotify_api_base_url: 'https://api.spotify.com/v1',
      spotify_access_token: 'token'
    )
  end

  it 'builds default graph and memoizes fetched dependencies' do
    theme = instance_double(YouFM::Styles::Theme)
    settings_store = instance_double(YouFM::Services::SettingsStore)
    spotify_client = instance_double(YouFM::Services::SpotifyClient)
    source = instance_double(YouFM::Services::MusicSources::SpotifySource)
    view_model = instance_double(YouFM::ViewModels::MainViewModel)
    main_window = instance_double(YouFM::Views::MainWindow)

    allow(YouFM::Styles::Theme).to receive(:new).with(name: 'dark').and_return(theme)
    allow(YouFM::Services::SettingsStore).to receive(:new).and_return(settings_store)
    allow(YouFM::Services::SpotifyClient).to receive(:new).with(
      access_token: 'token',
      base_url: 'https://api.spotify.com/v1'
    ).and_return(spotify_client)
    allow(YouFM::Services::MusicSources::SpotifySource).to receive(:new).with(client: spotify_client).and_return(source)
    allow(YouFM::ViewModels::MainViewModel).to receive(:new).with(source: source).and_return(view_model)
    allow(YouFM::Views::MainWindow).to receive(:new).with(
      view_model: view_model,
      theme: theme,
      settings_store: settings_store
    ).and_return(main_window)

    container = described_class.new(config: config)

    expect(container.fetch(:theme)).to equal(theme)
    expect(container.fetch('theme')).to equal(theme)
    expect(container.fetch(:main_window)).to equal(main_window)
    expect(container.fetch(:main_window)).to equal(main_window)
    expect(YouFM::Views::MainWindow).to have_received(:new).once
  end
end
