# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::ViewModels::MainViewModel do
  let(:source) do
    instance_double(
      YouFM::Services::MusicSources::SpotifySource,
      name: 'Spotify',
      configured?: true,
      connected?: false,
      resumable_session?: false
    )
  end
  let(:recommendation_generator) { instance_double(YouFM::Services::RecommendationGenerator) }
  let(:lastfm_authenticator) do
    instance_double(
      YouFM::Services::LastfmAuthenticator,
      connected?: false,
      configured?: false
    )
  end

  before do
    allow(Thread).to receive(:new).and_wrap_original do |_original, *args, &block|
      block.call(*args)
      instance_double(Thread)
    end
  end

  def build_view_model
    described_class.new(
      source: source,
      recommendation_generator: recommendation_generator,
      lastfm_authenticator: lastfm_authenticator
    )
  end

  it 'bootstraps from a saved session without opening auth flow' do
    device = YouFM::Models::Device.new(id: 'd1', name: 'MacBook', type: 'Computer', active: true, restricted: false)
    allow(source).to receive(:resumable_session?).and_return(true)
    allow(source).to receive(:available_devices).and_return([device])
    allow(source).to receive(:playlists).and_return([])
    allow(source).to receive(:queue).and_return([])
    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: nil, playing: false, progress_ms: 0)
    )

    view_model = build_view_model
    view_model.bootstrap

    expect(view_model.state.devices).to eq([device])
    expect(view_model.state.auth_status).to eq('Saved session available')
  end

  it 'searches and selects the first result' do
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    allow(source).to receive(:search_tracks).with('Track').and_return([track])

    view_model = build_view_model
    view_model.search('Track')

    expect(view_model.state.search_results).to eq([track])
    expect(view_model.state.selected_index).to eq(0)
  end

  it 'toggles playback using source pause and resume' do
    allow(source).to receive(:pause)
    allow(source).to receive(:resume)

    view_model = build_view_model
    view_model.state.playing = true
    view_model.toggle_playback
    expect(source).to have_received(:pause)

    view_model.toggle_playback
    expect(source).to have_received(:resume)
  end

  it 'connects Spotify and refreshes device and playlist state' do
    device = YouFM::Models::Device.new(id: 'd1', name: 'MacBook', type: 'Computer', active: true, restricted: false)
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me', tracks_total: 10)

    allow(source).to receive(:connect!)
    allow(source).to receive(:available_devices).and_return([device])
    allow(source).to receive(:playlists).and_return([playlist])
    allow(source).to receive(:queue).and_return([])
    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: nil, playing: false, progress_ms: 0)
    )
    allow(source).to receive(:connected?).and_return(true)

    view_model = build_view_model
    view_model.connect_spotify

    expect(view_model.state.connected).to be(true)
    expect(view_model.state.devices).to eq([device])
    expect(view_model.state.playlists).to eq([playlist])
  end

  it 'loads selected playlist tracks into the tracks list' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me', tracks_total: 10)
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    allow(source).to receive(:playlist_tracks).with(playlist).and_return([track])

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([track])
    expect(view_model.state.tracks_title).to eq('Playlist: Daily')
  end

  it 'disconnects Spotify and clears UI state' do
    allow(source).to receive(:disconnect!)
    allow(source).to receive(:connected?).and_return(true, false)
    allow(source).to receive(:configured?).and_return(true)

    view_model = build_view_model
    view_model.state.search_results = [
      YouFM::Models::Track.new(id: '1', title: 'Track', artists: ['Artist'], album: 'Album', uri: 'spotify:track:1', duration_ms: 1)
    ]
    view_model.state.selected_index = 0
    view_model.state.playing = true

    view_model.disconnect_spotify

    expect(source).to have_received(:disconnect!)
    expect(view_model.state.connected).to be(false)
    expect(view_model.state.search_results).to eq([])
    expect(view_model.state.playing).to be(false)
  end

  it 'shows a friendly playback error for unavailable devices' do
    allow(source).to receive(:play_track).and_raise(YouFM::Services::SpotifyClient::PlaybackUnavailableError, 'premium required')

    view_model = build_view_model
    view_model.state.search_results = [
      YouFM::Models::Track.new(id: '1', title: 'Track', artists: ['Artist'], album: 'Album', uri: 'spotify:track:1', duration_ms: 1)
    ]
    view_model.state.selected_index = 0

    view_model.play_selected

    expect(view_model.state.status_message).to include('Spotify playback is unavailable')
  end

  it 'optimistically appends a generated recommendation to the local queue' do
    current_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    recommended_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Recommended',
      artists: ['Another Artist'],
      album: 'Album 2',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:play_track)
    allow(source).to receive(:add_to_queue).with(recommended_track)
    allow(recommendation_generator).to receive(:generate_from_playlist).and_return(recommended_track)

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.state.selected_index = 0
    view_model.play_selected

    expect(view_model.state.queue_tracks).to include(recommended_track)
    expect(source).to have_received(:add_to_queue).with(recommended_track)
  end

  it 'can manually add a generated recommendation to the queue' do
    current_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    recommended_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Recommended',
      artists: ['Another Artist'],
      album: 'Album 2',
      uri: 'spotify:track:2',
      duration_ms: 1
    )

    allow(source).to receive(:add_to_queue).with(recommended_track)
    allow(recommendation_generator).to receive(:generate_from_playlist).and_return(recommended_track)

    view_model = build_view_model
    view_model.state.search_results = [current_track]

    view_model.generate_recommendation

    expect(source).to have_received(:add_to_queue).with(recommended_track)
    expect(view_model.state.queue_tracks).to include(recommended_track)
    expect(view_model.state.status_message).to include('Added recommendation to Spotify queue')
  end

  it 'refreshes queue without reintroducing the currently playing track' do
    old_track = YouFM::Models::Track.new(
      id: 'old-track',
      title: 'Old Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:old-track',
      duration_ms: 1
    )
    next_track = YouFM::Models::Track.new(
      id: 'next-track',
      title: 'Next Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:next-track',
      duration_ms: 1
    )

    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: old_track, playing: true, progress_ms: 0)
    )
    allow(source).to receive(:queue).and_return([next_track])
    allow(recommendation_generator).to receive(:generate_from_playlist).and_return(nil)

    view_model = build_view_model
    view_model.state.search_results = [old_track]

    view_model.refresh_playback
    view_model.refresh_queue

    expect(view_model.state.queue_tracks).to eq([next_track])
  end

  it 'generates the next recommendation when Spotify playback changes tracks' do
    current_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    next_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Next Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    recommended_track = YouFM::Models::Track.new(
      id: '3',
      title: 'Recommended',
      artists: ['Another Artist'],
      album: 'Album 2',
      uri: 'spotify:track:3',
      duration_ms: 1
    )

    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: current_track, playing: true, progress_ms: 0),
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: next_track, playing: true, progress_ms: 0)
    )
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me', tracks_total: 2)
    allow(source).to receive(:add_to_queue).with(recommended_track)
    allow(recommendation_generator).to receive(:generate_from_playlist).and_return(nil, recommended_track)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.state.selected_playlist_index = 0
    view_model.state.search_results = [current_track, next_track]

    view_model.refresh_playback
    view_model.refresh_playback

    expect(source).to have_received(:add_to_queue).with(recommended_track).once
    expect(view_model.state.queue_tracks).to include(recommended_track)
  end

  it 'surfaces when auto-recommendation could not find a suitable track' do
    current_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    next_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Next Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )

    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: current_track, playing: true, progress_ms: 0),
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: next_track, playing: true, progress_ms: 0)
    )
    allow(recommendation_generator).to receive(:generate_from_playlist).and_return(nil)

    view_model = build_view_model
    view_model.state.search_results = [current_track, next_track]

    view_model.refresh_playback
    view_model.refresh_playback

    expect(view_model.state.status_message).to eq('Auto-recommendation skipped: Last.fm/Spotify did not return a suitable track')
  end
end
