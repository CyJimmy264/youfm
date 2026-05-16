# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::RecommendationTrackMatcher do
  let(:spotify_client) { instance_double(YouFM::Services::SpotifyClient) }

  def build_track(id:, title:, artist:, explicit: false)
    YouFM::Models::Track.new(
      id: id,
      title: title,
      artists: [artist],
      album: 'Album',
      uri: "spotify:track:#{id}",
      duration_ms: 1,
      explicit: explicit
    )
  end

  it 'chooses the best matching Spotify track instead of the first acceptable one' do
    weaker_match = build_track(
      id: 'weaker',
      title: 'Dreamcraft - Original Deep Mix',
      artist: 'Following Light'
    )
    stronger_match = build_track(
      id: 'stronger',
      title: 'Dreamcraft - Original Deep Mix',
      artist: 'Following Light, MDeco'
    )
    matcher = described_class.new(spotify_client: spotify_client)

    allow(spotify_client).to receive(:search_tracks)
      .with('Dreamcraft - Original Deep Mix artist:Following Light', limit: 10)
      .and_return([weaker_match, stronger_match])

    result = matcher.spotify_track_candidate_for(
      artist_name: 'Following Light',
      track_name: 'Dreamcraft - Original Deep Mix',
      blocked_track_ids: Set.new
    )

    expect(result).to eq(stronger_match)
  end

  it 'still ignores blocked and explicit tracks while ranking candidates' do
    blocked_match = build_track(id: 'blocked', title: 'Song', artist: 'Artist')
    explicit_match = build_track(id: 'explicit', title: 'Song', artist: 'Artist', explicit: true)
    clean_match = build_track(id: 'clean', title: 'Song', artist: 'Artist')
    matcher = described_class.new(spotify_client: spotify_client)

    allow(spotify_client).to receive(:search_tracks)
      .with('Song artist:Artist', limit: 10)
      .and_return([blocked_match, explicit_match, clean_match])

    result = matcher.spotify_track_candidate_for(
      artist_name: 'Artist',
      track_name: 'Song',
      blocked_track_ids: Set['blocked']
    )

    expect(result).to eq(clean_match)
  end

  it 'treats accented and non-accented text as equivalent' do
    accented_match = build_track(id: 'accented', title: 'Café Lounge', artist: 'Artist')
    matcher = described_class.new(spotify_client: spotify_client)

    allow(spotify_client).to receive(:search_tracks)
      .with('Cafe Lounge artist:Artist', limit: 10)
      .and_return([accented_match])

    result = matcher.spotify_track_candidate_for(
      artist_name: 'Artist',
      track_name: 'Cafe Lounge',
      blocked_track_ids: Set.new
    )

    expect(result).to eq(accented_match)
  end

  it 'filters out title-blacklisted tracks' do
    blocked_title = build_track(id: 'blocked', title: 'Song - Live', artist: 'Artist')
    clean_match = build_track(id: 'clean', title: 'Song', artist: 'Artist')
    matcher = described_class.new(spotify_client: spotify_client, title_blacklist: ['live'])

    allow(spotify_client).to receive(:search_tracks)
      .with('Song artist:Artist', limit: 10)
      .and_return([blocked_title, clean_match])

    result = matcher.spotify_track_candidate_for(
      artist_name: 'Artist',
      track_name: 'Song',
      blocked_track_ids: Set.new
    )

    expect(result).to eq(clean_match)
  end
end
