# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::SpotifyClient do
  describe '#search_tracks' do
    it 'maps Spotify track payloads into track models' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '200', body: JSON.dump(
        'tracks' => {
          'items' => [
            {
              'id' => '1',
              'name' => 'Track',
              'artists' => [{ 'name' => 'Artist' }],
              'album' => { 'name' => 'Album' },
              'uri' => 'spotify:track:1',
              'duration_ms' => 123_000
            }
          ]
        }
      ))
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      result = client.search_tracks('track')

      expect(result.length).to eq(1)
      expect(result.first.display_label).to eq('Track - Artist')
    end
  end

  describe '#current_playback' do
    it 'returns an empty playback state on 204' do
      client = described_class.new(access_token: 'token', base_url: 'https://api.spotify.test/v1')
      response = instance_double(Net::HTTPResponse, code: '204', body: '')
      http = instance_double(Net::HTTP, request: response)

      allow(Net::HTTP).to receive(:start).and_yield(http)

      playback = client.current_playback

      expect(playback.track).to be_nil
      expect(playback.playing).to be(false)
    end
  end
end
