# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::RecommendationGenerator do
  let(:lastfm_client) { instance_double(YouFM::Services::LastfmClient) }
  let(:spotify_client) { instance_double(YouFM::Services::SpotifyClient) }

  def build_track(id:, title:, artist:, uri:)
    YouFM::Models::Track.new(
      id: id,
      title: title,
      artists: [artist],
      album: 'Album',
      uri: uri,
      duration_ms: 1
    )
  end

  it 'picks similar artists from a random window across the full pool' do
    seed_track = build_track(id: 'seed', title: 'Seed', artist: 'Seed Artist', uri: 'spotify:track:seed')
    similar_artists = Array.new(25) do |index|
      YouFM::Services::LastfmClient::SimilarArtist.new(name: "Similar #{index}", match: 0.5)
    end
    top_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Top Track', playcount: 100, listeners: 10)
    recommended_track = build_track(id: 'recommended', title: 'Recommended', artist: 'Similar 12', uri: 'spotify:track:recommended')

    allow(lastfm_client).to receive(:get_similar_artists).with('Seed Artist').and_return(similar_artists)
    allow(lastfm_client).to receive(:get_top_tracks).with('Similar 12', period: '12month', limit: 20).and_return([top_track])
    allow(spotify_client).to receive(:search_tracks).with('Top Track artist:Similar 12', limit: 3).and_return([recommended_track])
    allow_any_instance_of(described_class).to receive(:rand).with(25).and_return(12)

    generator = described_class.new(lastfm_client:, spotify_client:)
    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(recommended_track)
  end
end
