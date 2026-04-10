# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Container do
  let(:config) do
    instance_double(
      YouFM::Configuration,
      theme_name: 'dark',
      spotify_api_base_url: 'https://api.spotify.com/v1',
      spotify_accounts_base_url: 'https://accounts.spotify.com',
      spotify_access_token: 'token',
      spotify_client_id: 'client-id',
      spotify_redirect_uri: 'http://127.0.0.1:8989/callback',
      spotify_scopes: %w[user-read-playback-state],
      lastfm_api_key: 'lastfm-key',
      lastfm_secret: 'lastfm-secret'
    )
  end

  it 'builds default graph and memoizes fetched dependencies' do
    theme = instance_double(YouFM::Styles::Theme)
    settings_store = instance_double(YouFM::Services::SettingsStore)
    token_store = instance_double(YouFM::Services::SpotifyTokenStore)
    lastfm_token_store = instance_double(YouFM::Services::LastfmTokenStore, load: { 'key' => 'session-key' })
    lastfm_similar_artists_cache = instance_double(YouFM::Services::LastfmSimilarArtistsCache)
    browser_launcher = instance_double(YouFM::Services::BrowserLauncher)
    authenticator = instance_double(YouFM::Services::SpotifyAuthenticator)
    spotify_client = instance_double(YouFM::Services::SpotifyClient)
    lastfm_client = instance_double(YouFM::Services::LastfmClient)
    lastfm_authenticator = instance_double(YouFM::Services::LastfmAuthenticator)
    recommendation_generator = instance_double(YouFM::Services::RecommendationGenerator)
    source = instance_double(YouFM::Services::MusicSources::SpotifySource)
    view_model = instance_double(YouFM::ViewModels::MainViewModel)
    main_window = instance_double(YouFM::Views::MainWindow)

    allow(YouFM::Styles::Theme).to receive(:new).with(name: 'dark').and_return(theme)
    allow(YouFM::Services::SettingsStore).to receive(:new).and_return(settings_store)
    allow(YouFM::Services::SpotifyTokenStore).to receive(:new).and_return(token_store)
    allow(YouFM::Services::LastfmTokenStore).to receive(:new).and_return(lastfm_token_store)
    allow(YouFM::Services::LastfmSimilarArtistsCache).to receive(:new).and_return(lastfm_similar_artists_cache)
    allow(YouFM::Services::BrowserLauncher).to receive(:new).and_return(browser_launcher)
    allow(YouFM::Services::SpotifyAuthenticator).to receive(:new).with(
      client_id: 'client-id',
      redirect_uri: 'http://127.0.0.1:8989/callback',
      scopes: %w[user-read-playback-state],
      accounts_base_url: 'https://accounts.spotify.com',
      token_store: token_store,
      browser_launcher: browser_launcher
    ).and_return(authenticator)
    allow(YouFM::Services::SpotifyClient).to receive(:new).with(
      access_token: 'token',
      base_url: 'https://api.spotify.com/v1',
      token_store: token_store,
      authenticator: authenticator
    ).and_return(spotify_client)
    allow(YouFM::Services::LastfmClient).to receive(:new).with(
      api_key: 'lastfm-key',
      secret: 'lastfm-secret',
      session_key: 'session-key',
      similar_artists_cache: lastfm_similar_artists_cache
    ).and_return(lastfm_client)
    allow(YouFM::Services::LastfmAuthenticator).to receive(:new).with(
      api_key: 'lastfm-key',
      secret: 'lastfm-secret',
      lastfm_client: lastfm_client,
      token_store: lastfm_token_store,
      browser_launcher: browser_launcher
    ).and_return(lastfm_authenticator)
    allow(YouFM::Services::RecommendationGenerator).to receive(:new).with(
      lastfm_client: lastfm_client,
      spotify_client: spotify_client
    ).and_return(recommendation_generator)
    allow(YouFM::Services::MusicSources::SpotifySource).to receive(:new).with(client: spotify_client).and_return(source)
    allow(YouFM::ViewModels::MainViewModel).to receive(:new).with(
      source: source,
      recommendation_generator: recommendation_generator,
      lastfm_authenticator: lastfm_authenticator
    ).and_return(view_model)
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
