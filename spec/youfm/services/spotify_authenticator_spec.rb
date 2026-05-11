# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::SpotifyAuthenticator do
  it 'refreshes persisted tokens and keeps refresh_token when Spotify omits it' do
    token_store = instance_double(YouFM::Services::SpotifyTokenStore)
    browser_launcher = instance_double(YouFM::Services::BrowserLauncher)
    response = instance_double(
      YouFM::Services::PersistentHttpClient::Response,
      code: '200',
      body: JSON.dump('access_token' => 'new-token', 'token_type' => 'Bearer', 'expires_in' => 3600)
    )
    http_client = instance_double(YouFM::Services::PersistentHttpClient, request: response)
    authenticator = described_class.new(
      client_id: 'client-id',
      redirect_uri: 'http://127.0.0.1:8989/callback',
      scopes: %w[user-read-playback-state],
      accounts_base_url: 'https://accounts.spotify.test',
      token_store: token_store,
      browser_launcher: browser_launcher,
      http_client: http_client
    )

    allow(token_store).to receive(:load).and_return({ 'refresh_token' => 'refresh-token' },
                                                    { 'access_token' => 'new-token',
                                                      'refresh_token' => 'refresh-token' })
    allow(token_store).to receive(:save)

    payload = authenticator.refresh!('refresh-token')

    expect(token_store).to have_received(:save)
    expect(payload['access_token']).to eq('new-token')
    expect(payload['refresh_token']).to eq('refresh-token')
  end
end
