# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::RecommendationGenerator do
  let(:lastfm_client) { instance_double(YouFM::Services::LastfmClient) }
  let(:spotify_client) { instance_double(YouFM::Services::SpotifyClient) }
  let(:random) { instance_double(Random) }

  def build_track(id:, title:, artist:, uri:, explicit: false)
    YouFM::Models::Track.new(
      id: id,
      title: title,
      artists: [artist],
      album: 'Album',
      uri: uri,
      duration_ms: 1,
      explicit: explicit
    )
  end

  it 'picks similar artists from a random window across the full pool' do
    seed_track = build_track(id: 'seed', title: 'Seed', artist: 'Seed Artist', uri: 'spotify:track:seed')
    similar_artists = Array.new(25) do |index|
      YouFM::Services::LastfmClient::SimilarArtist.new(name: "Similar #{index}", match: 0.5)
    end
    top_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Top Track', playcount: 100, listeners: 10)
    recommended_track = build_track(id: 'recommended', title: 'Top Track', artist: 'Similar 12',
                                    uri: 'spotify:track:recommended')

    allow(lastfm_client).to receive(:get_similar_artists).with('Seed Artist', limit: 200).and_return(similar_artists)
    allow(lastfm_client).to receive(:get_top_tracks).and_return([])
    allow(lastfm_client).to receive(:get_top_tracks).with('Similar 12', period: '12month',
                                                                        limit: 20).and_return([top_track])
    allow(spotify_client).to receive(:search_tracks).with('Top Track artist:Similar 12',
                                                          limit: 10).and_return([recommended_track])
    allow(random).to receive(:rand).with(25).and_return(12)
    generator = described_class.new(lastfm_client:, spotify_client:, random:)
    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(recommended_track)
  end

  it 'skips loose Spotify matches and keeps searching for an exact enough candidate' do
    seed_track = build_track(id: 'seed', title: 'Seed', artist: 'Seed Artist', uri: 'spotify:track:seed')
    first_similar_artist = YouFM::Services::LastfmClient::SimilarArtist.new(name: 'Similar Artist', match: 0.5)
    second_similar_artist = YouFM::Services::LastfmClient::SimilarArtist.new(name: 'Exact Artist', match: 0.4)
    first_top_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Song One', playcount: 100, listeners: 10)
    second_top_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Song Two', playcount: 90, listeners: 9)
    loose_match = build_track(id: 'loose', title: 'Different Song', artist: 'Similar', uri: 'spotify:track:loose')
    exact_match = build_track(id: 'exact', title: 'Song Two', artist: 'Exact Artist', uri: 'spotify:track:exact')

    allow(lastfm_client).to receive(:get_similar_artists).with('Seed Artist',
                                                               limit: 200).and_return([first_similar_artist,
                                                                                       second_similar_artist])
    allow(lastfm_client).to receive(:get_top_tracks).with('Similar Artist', period: '12month',
                                                                            limit: 20).and_return([first_top_track])
    allow(lastfm_client).to receive(:get_top_tracks).with('Exact Artist', period: '12month',
                                                                          limit: 20).and_return([second_top_track])
    allow(spotify_client).to receive(:search_tracks).with('Song One artist:Similar Artist',
                                                          limit: 10).and_return([loose_match])
    allow(spotify_client).to receive(:search_tracks).with('Song Two artist:Exact Artist',
                                                          limit: 10).and_return([exact_match])
    allow(random).to receive(:rand).with(2).and_return(0)
    generator = described_class.new(lastfm_client:, spotify_client:, random:)
    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(exact_match)
  end

  it 'skips explicit Spotify matches and keeps searching for a clean candidate' do
    seed_track = build_track(id: 'seed', title: 'Seed', artist: 'Seed Artist', uri: 'spotify:track:seed')
    similar_artist = YouFM::Services::LastfmClient::SimilarArtist.new(name: 'Similar Artist', match: 0.5)
    top_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Song One', playcount: 100, listeners: 10)
    explicit_match = build_track(id: 'explicit', title: 'Song One', artist: 'Similar Artist',
                                 uri: 'spotify:track:explicit', explicit: true)
    clean_match = build_track(id: 'clean', title: 'Song One', artist: 'Similar Artist', uri: 'spotify:track:clean')

    allow(lastfm_client).to receive(:get_similar_artists).with('Seed Artist', limit: 200).and_return([similar_artist])
    allow(lastfm_client).to receive(:get_top_tracks).with('Similar Artist', period: '12month',
                                                                            limit: 20).and_return([top_track])
    allow(spotify_client).to receive(:search_tracks).with('Song One artist:Similar Artist',
                                                          limit: 10).and_return([explicit_match, clean_match])
    allow(random).to receive(:rand).with(1).and_return(0)
    generator = described_class.new(lastfm_client:, spotify_client:, random:)

    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(clean_match)
  end

  it 'moves to the next similar artist after three failed top-track attempts' do
    seed_track = build_track(id: 'seed', title: 'Seed', artist: 'Seed Artist', uri: 'spotify:track:seed')
    first_similar_artist = YouFM::Services::LastfmClient::SimilarArtist.new(name: 'First Artist', match: 0.5)
    second_similar_artist = YouFM::Services::LastfmClient::SimilarArtist.new(name: 'Second Artist', match: 0.4)
    first_artist_tracks = [
      YouFM::Services::LastfmClient::TopTrack.new(name: 'Miss One', playcount: 100, listeners: 10),
      YouFM::Services::LastfmClient::TopTrack.new(name: 'Miss Two', playcount: 90, listeners: 9),
      YouFM::Services::LastfmClient::TopTrack.new(name: 'Miss Three', playcount: 80, listeners: 8),
      YouFM::Services::LastfmClient::TopTrack.new(name: 'Miss Four', playcount: 70, listeners: 7)
    ]
    second_artist_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Hit Song', playcount: 60, listeners: 6)
    second_artist_tracks = [second_artist_track]
    loose_match = build_track(id: 'loose', title: 'Different Song', artist: 'First', uri: 'spotify:track:loose')
    exact_match = build_track(id: 'exact', title: 'Hit Song', artist: 'Second Artist', uri: 'spotify:track:exact')

    allow(lastfm_client).to receive(:get_similar_artists).with('Seed Artist',
                                                               limit: 200).and_return([first_similar_artist,
                                                                                       second_similar_artist])
    allow(lastfm_client).to receive(:get_top_tracks).with('First Artist', period: '12month',
                                                                          limit: 20).and_return(first_artist_tracks)
    allow(lastfm_client).to receive(:get_top_tracks).with('Second Artist', period: '12month',
                                                                           limit: 20).and_return(second_artist_tracks)
    allow(spotify_client).to receive(:search_tracks).with('Miss One artist:First Artist',
                                                          limit: 10).and_return([loose_match])
    allow(spotify_client).to receive(:search_tracks).with('Miss Two artist:First Artist',
                                                          limit: 10).and_return([loose_match])
    allow(spotify_client).to receive(:search_tracks).with('Miss Three artist:First Artist',
                                                          limit: 10).and_return([loose_match])
    allow(spotify_client).to receive(:search_tracks).with('Hit Song artist:Second Artist',
                                                          limit: 10).and_return([exact_match])
    allow(first_artist_tracks).to receive(:shuffle).and_return(first_artist_tracks)
    allow(second_artist_tracks).to receive(:shuffle).and_return(second_artist_tracks)

    allow(random).to receive(:rand).with(2).and_return(0)
    generator = described_class.new(lastfm_client:, spotify_client:, random:)
    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(exact_match)
    expect(spotify_client).not_to have_received(:search_tracks).with('Miss Four artist:First Artist', limit: 10)
  end

  it 'uses the configured similar artist pool limit when asking Last.fm for candidates' do
    seed_track = build_track(id: 'seed', title: 'Seed', artist: 'Seed Artist', uri: 'spotify:track:seed')
    similar_artist = YouFM::Services::LastfmClient::SimilarArtist.new(name: 'Similar Artist', match: 0.5)
    top_track = YouFM::Services::LastfmClient::TopTrack.new(name: 'Top Track', playcount: 100, listeners: 10)
    recommended_track = build_track(id: 'recommended', title: 'Top Track', artist: 'Similar Artist',
                                    uri: 'spotify:track:recommended')

    allow(lastfm_client).to receive(:get_similar_artists).with('Seed Artist', limit: 350).and_return([similar_artist])
    allow(lastfm_client).to receive(:get_top_tracks).with('Similar Artist', period: '12month',
                                                                            limit: 20).and_return([top_track])
    allow(spotify_client).to receive(:search_tracks).with('Top Track artist:Similar Artist',
                                                          limit: 10).and_return([recommended_track])
    allow(random).to receive(:rand).with(1).and_return(0)
    generator = described_class.new(lastfm_client:, spotify_client:, similar_artist_pool_limit: 350, random:)
    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(recommended_track)
    expect(generator.similar_artist_pool_limit).to eq(350)
  end

  it 'can use track.getSimilar as an enabled recommendation strategy' do
    seed_track = build_track(id: 'seed', title: 'Seed Song', artist: 'Seed Artist', uri: 'spotify:track:seed')
    similar_track = YouFM::Services::LastfmClient::SimilarTrack.new('Similar Song', 'Similar Artist', 0.7)
    recommended_track = build_track(id: 'recommended', title: 'Similar Song', artist: 'Similar Artist',
                                    uri: 'spotify:track:recommended')

    allow(lastfm_client)
      .to receive(:get_similar_tracks)
      .with('Seed Artist', 'Seed Song', limit: 20)
      .and_return([similar_track])
    allow(lastfm_client).to receive(:get_similar_artists)
    allow(spotify_client)
      .to receive(:search_tracks)
      .with('Similar Song artist:Similar Artist', limit: 10)
      .and_return([recommended_track])

    generator = described_class.new(
      lastfm_client: lastfm_client,
      spotify_client: spotify_client,
      enabled_strategy_names: [:track_similar]
    )
    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(recommended_track)
  end

  it 'uses the selected generator for the chosen seed source' do
    seed_track = build_track(id: 'seed', title: 'Seed Song', artist: 'Seed Artist', uri: 'spotify:track:seed')
    similar_track = YouFM::Services::LastfmClient::SimilarTrack.new('Similar Song', 'Similar Artist', 0.7)
    recommended_track = build_track(id: 'recommended', title: 'Similar Song', artist: 'Similar Artist',
                                    uri: 'spotify:track:recommended')
    generator = described_class.new(
      lastfm_client: lastfm_client,
      spotify_client: spotify_client,
      enabled_seed_source_names: [:current_playlist],
      enabled_generator_names: %i[artist_similar_top_tracks track_similar],
      generator_weights: { artist_similar_top_tracks: 1, track_similar: 1 },
      random: random
    )

    allow(random).to receive(:rand).with(2).and_return(1)
    allow(lastfm_client)
      .to receive(:get_similar_tracks)
      .with('Seed Artist', 'Seed Song', limit: 20)
      .and_return([similar_track])
    allow(lastfm_client).to receive(:get_similar_artists).and_return([])
    allow(spotify_client)
      .to receive(:search_tracks)
      .with('Similar Song artist:Similar Artist', limit: 10)
      .and_return([recommended_track])

    result = generator.generate_from_playlist([seed_track], playlist_name: 'Daily')

    expect(result).to eq(recommended_track)
    expect(lastfm_client).not_to have_received(:get_similar_artists)
  end

  it 'returns nil when all strategies are disabled' do
    seed_track = build_track(id: 'seed', title: 'Seed Song', artist: 'Seed Artist', uri: 'spotify:track:seed')
    generator = described_class.new(lastfm_client: lastfm_client, spotify_client: spotify_client,
                                    enabled_strategy_names: [])

    expect(generator.generate_from_playlist([seed_track], playlist_name: 'Daily')).to be_nil
  end

  it 'can use a random recent Last.fm track as a recommendation strategy' do
    seed_track = build_track(id: 'seed', title: 'Seed Song', artist: 'Seed Artist', uri: 'spotify:track:seed')
    first_page = YouFM::Services::LastfmClient::UserTracksPage.new([], 1, 10)
    recent_track = YouFM::Services::LastfmClient::RecentTrack.new('Recent Song', 'Recent Artist', 'Album', '1710000000')
    selected_page = YouFM::Services::LastfmClient::UserTracksPage.new([recent_track], 3, 10)
    recommended_track = build_track(id: 'recommended', title: 'Recent Song', artist: 'Recent Artist',
                                    uri: 'spotify:track:recommended')

    allow(lastfm_client).to receive(:get_recent_tracks).with(page: 1, limit: 10).and_return(first_page)
    allow(lastfm_client).to receive(:get_recent_tracks).with(page: 3, limit: 10).and_return(selected_page)
    allow(random).to receive(:rand).with(10).and_return(2)
    allow(spotify_client).to receive(:search_tracks).with('Recent Song artist:Recent Artist', limit: 10).and_return(
      [recommended_track]
    )

    generator = described_class.new(
      lastfm_client: lastfm_client,
      spotify_client: spotify_client,
      enabled_strategy_names: [:recent_tracks],
      random: random
    )

    expect(generator.generate_from_playlist([seed_track], playlist_name: 'Daily')).to eq(recommended_track)
  end

  it 'can use a seedless recent-tracks strategy when no playlist tracks are loaded' do
    recent_track = YouFM::Services::LastfmClient::RecentTrack.new('Recent Song', 'Recent Artist', 'Album', '1710000000')
    selected_page = YouFM::Services::LastfmClient::UserTracksPage.new([recent_track], 1, 1)
    recommended_track = build_track(id: 'recommended', title: 'Recent Song', artist: 'Recent Artist',
                                    uri: 'spotify:track:recommended')

    allow(lastfm_client).to receive(:get_recent_tracks).with(page: 1, limit: 10).and_return(selected_page)
    allow(spotify_client).to receive(:search_tracks).with('Recent Song artist:Recent Artist', limit: 10).and_return(
      [recommended_track]
    )

    generator = described_class.new(
      lastfm_client: lastfm_client,
      spotify_client: spotify_client,
      enabled_strategy_names: [:recent_tracks],
      random: random
    )

    recommendation = generator.generate_with_seed([], playlist_name: 'Daily')

    expect(recommendation.track).to eq(recommended_track)
    expect(recommendation.seed_track).to be_nil
    expect(recommendation.seed_label).to include('Recent Song — Recent Artist')
  end

  it 'can use a seedless loved-tracks strategy when no playlist tracks are loaded' do
    loved_track = YouFM::Services::LastfmClient::LovedTrack.new('Loved Song', 'Loved Artist', 'Album', '1711000000')
    selected_page = YouFM::Services::LastfmClient::UserTracksPage.new([loved_track], 1, 1)
    recommended_track = build_track(id: 'recommended', title: 'Loved Song', artist: 'Loved Artist',
                                    uri: 'spotify:track:recommended')

    allow(lastfm_client).to receive(:get_loved_tracks).with(page: 1, limit: 10).and_return(selected_page)
    allow(spotify_client).to receive(:search_tracks).with('Loved Song artist:Loved Artist', limit: 10).and_return(
      [recommended_track]
    )

    generator = described_class.new(
      lastfm_client: lastfm_client,
      spotify_client: spotify_client,
      enabled_strategy_names: [:loved_tracks],
      random: random
    )

    recommendation = generator.generate_with_seed([], playlist_name: 'Daily')

    expect(recommendation.track).to eq(recommended_track)
    expect(recommendation.seed_track).to be_nil
    expect(recommendation.seed_label).to include('Loved Song — Loved Artist')
    expect(recommendation.seed_label).to include('loved tracks')
  end
end
