# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe YouFM::ViewModels::MainViewModel do
  let(:source) do
    instance_double(
      YouFM::Services::MusicSources::SpotifySource,
      name: 'Spotify',
      configured?: true,
      connected?: false,
      resumable_session?: false,
      cached_playlist_tracks_page: nil,
      cached_playlist_tracks: nil
    )
  end
  let(:recommendation_generator) do
    instance_double(
      YouFM::Services::RecommendationGenerator,
      similar_artist_pool_limit: 200,
      enabled_strategy_names: [:artist_similar_top_tracks],
      generator_weights: {},
      exclude_explicit?: true
    )
  end
  let(:recommendation_coordinator) do
    YouFM::Services::RecommendationCoordinator.new(
      recommendation_generator: recommendation_generator,
      source: source,
      seed_store: recommendation_seed_store
    )
  end
  let(:recommendation_seed_store) do
    instance_double(
      YouFM::Services::RecommendationSeedStore,
      fetch: nil,
      save: nil,
      existing_for: {}
    )
  end
  let(:lastfm_authenticator) do
    instance_double(
      YouFM::Services::LastfmAuthenticator,
      connected?: false,
      configured?: false
    )
  end
  let(:recommendation_history_store) do
    instance_double(YouFM::Services::RecommendationHistoryStore, load: [], remember: nil)
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
      recommendation_coordinator: recommendation_coordinator,
      recommendation_seed_store: recommendation_seed_store,
      recommended_queue_store: recommended_queue_store,
      recommendation_history_store: recommendation_history_store,
      lastfm_authenticator: lastfm_authenticator
    )
  end

  def recommended_queue_store
    @recommended_queue_store ||= instance_double(
      YouFM::Services::RecommendedQueueStore,
      load: { track_ids: [], tracks: [], seeds: {} },
      save: nil,
      clear: nil
    )
  end

  def build_recommendation(track:, seed_track:)
    YouFM::Services::RecommendationGenerator::Recommendation.new(track: track, seed_track: seed_track)
  end

  it 'bootstraps from a saved session without opening auth flow' do
    device = YouFM::Models::Device.new(id: 'd1', name: 'MacBook', type: 'Computer', active: true, restricted: false)
    allow(source)
      .to receive_messages(
        resumable_session?: true, available_devices: [device], playlists: [], queue: [],
        current_playback: YouFM::Models::PlaybackState.new(
          device_name: 'MacBook', track: nil, playing: false, progress_ms: 0
        )
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

  it 'updates the similar artist pool limit through the recommendation generator' do
    allow(recommendation_generator).to receive(:similar_artist_pool_limit=)

    view_model = build_view_model
    result = view_model.update_similar_artist_pool_limit('350')

    expect(result).to eq(350)
    expect(recommendation_generator).to have_received(:similar_artist_pool_limit=).with(350)
    expect(view_model.state.status_message).to eq('Similar artist pool limit set to 350')
  end

  it 'updates enabled recommendation strategies through the recommendation generator' do
    allow(recommendation_generator).to receive(:enabled_seed_source_names=) do |names|
      allow(recommendation_generator).to receive(:enabled_seed_source_names).and_return(names.map(&:to_sym))
    end
    allow(recommendation_generator).to receive(:enabled_generator_names=) do |names|
      allow(recommendation_generator).to receive(:enabled_generator_names).and_return(names.map(&:to_sym))
      allow(recommendation_generator).to receive(:enabled_strategy_names).and_return(names.map(&:to_sym))
    end
    allow(recommendation_generator).to receive(:generator_weights=) do |weights|
      allow(recommendation_generator).to receive(:generator_weights).and_return(weights.transform_keys(&:to_sym))
    end

    view_model = build_view_model
    result = view_model.update_enabled_recommendation_strategy_names(%w[artist_similar_top_tracks track_similar])

    expect(result).to eq(%i[artist_similar_top_tracks track_similar])
    expect(recommendation_generator).to have_received(:enabled_seed_source_names=).with([:current_playlist])
    expect(recommendation_generator).to have_received(:enabled_generator_names=).with(
      %i[artist_similar_top_tracks track_similar]
    )
    expect(recommendation_generator).to have_received(:generator_weights=).with(
      artist_similar_top_tracks: 1,
      track_similar: 1
    )
    expect(view_model.state.status_message).to include('Seed sources: Current playlist / tracks list')
    expect(view_model.state.status_message).to include('Similar artist top tracks×1, Similar tracks×1')
  end

  it 'updates the explicit content filter through the recommendation generator' do
    allow(recommendation_generator).to receive(:exclude_explicit=) do |value|
      allow(recommendation_generator).to receive(:exclude_explicit?).and_return(value)
    end

    view_model = build_view_model
    view_model.filter_explicit_content = false

    expect(recommendation_generator).to have_received(:exclude_explicit=).with(false)
    expect(view_model.state.status_message).to eq('Explicit content filter disabled')
  end

  it 'updates seed replay settings' do
    view_model = build_view_model
    result = view_model.update_seed_replay_settings(enabled: true, interval: '4')

    expect(result).to eq(enabled: true, interval: 4)
    expect(view_model.state.status_message).to eq('Seed replay enabled: every 4 recommendation(s)')
  end

  it 'updates the minimum recommended queue size' do
    view_model = build_view_model
    result = view_model.update_minimum_recommended_queue_size('3')

    expect(result).to eq(3)
    expect(view_model.minimum_recommended_queue_size).to eq(3)
    expect(view_model.state.status_message).to eq('Minimum recommended queue size set to 3')
  end

  it 'updates the maximum recommended queue size' do
    view_model = build_view_model
    result = view_model.update_maximum_recommended_queue_size('7')

    expect(result).to eq(7)
    expect(view_model.maximum_recommended_queue_size).to eq(7)
    expect(view_model.state.status_message).to eq('Maximum recommended queue size set to 7')
  end

  it 'blocks tracks that were already stored in recommendation history' do
    historical_track = YouFM::Models::Track.new(
      id: 'history-track',
      title: 'History Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:history-track',
      duration_ms: 1
    )
    seed_track = YouFM::Models::Track.new(
      id: 'seed',
      title: 'Seed',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:seed',
      duration_ms: 1
    )
    allow(recommendation_history_store).to receive(:load).and_return(['history-track'])
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: historical_track, seed_track: seed_track),
      nil
    )

    view_model = build_view_model
    view_model.state.search_results = [seed_track]

    expect(view_model.generate_recommendation).to eq(
      'Recommendation not added: Last.fm/Spotify did not return a suitable track'
    )
  end

  it 'persists newly queued recommendation ids into recommendation history' do
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
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: recommended_track, seed_track: current_track)
    )

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.generate_recommendation

    expect(recommendation_history_store).to have_received(:remember).with('2')
  end

  it 'rejects invalid minimum recommended queue sizes' do
    view_model = build_view_model
    result = view_model.update_minimum_recommended_queue_size('0')

    expect(result).to eq('Minimum recommended queue size must be a positive integer')
    expect(view_model.minimum_recommended_queue_size).to eq(1)
  end

  it 'does not schedule queue fill when the local queue is already at the maximum size' do
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
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: recommended_track, seed_track: current_track)
    )

    view_model = build_view_model
    view_model.update_minimum_recommended_queue_size('3')
    view_model.update_maximum_recommended_queue_size('1')
    view_model.state.search_results = [current_track]
    view_model.generate_recommendation

    expect(recommendation_generator).to have_received(:generate_with_seed).once
  end

  it 'does not auto-generate on playback change when the queue is already at the maximum size' do
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
    queued_track = YouFM::Models::Track.new(
      id: '3',
      title: 'Queued Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:3',
      duration_ms: 1
    )

    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: current_track, playing: true, progress_ms: 0),
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: next_track, playing: true, progress_ms: 0)
    )
    allow(recommendation_generator).to receive(:generate_with_seed)

    view_model = build_view_model
    view_model.update_maximum_recommended_queue_size('1')
    view_model.state.queue_tracks = [queued_track]
    view_model.state.search_results = [current_track, next_track]

    view_model.refresh_playback
    view_model.refresh_playback

    expect(recommendation_generator).not_to have_received(:generate_with_seed)
  end

  it 'rejects invalid similar artist pool limits' do
    allow(recommendation_generator).to receive(:similar_artist_pool_limit=)

    view_model = build_view_model
    result = view_model.update_similar_artist_pool_limit('0')

    expect(result).to eq('Similar artist pool limit must be a positive integer')
    expect(recommendation_generator).not_to have_received(:similar_artist_pool_limit=)
  end

  it 'logs status changes to stdout' do
    view_model = build_view_model
    initial_revision = view_model.revision

    expect { view_model.status = 'Visible status' }.to output(
      /\A\[\d{4}-\d{2}-\d{2}T[^\]]+\] \[youfm\] status: Visible status\n\z/
    ).to_stdout
    changed_revision = view_model.revision
    expect { view_model.status = 'Visible status' }.not_to output.to_stdout
    expect(view_model.state.status_message).to eq('Visible status')
    expect(changed_revision).to be > initial_revision
    expect(view_model.revision).to be > changed_revision
  end

  it 'connects Spotify and refreshes device and playlist state' do
    device = YouFM::Models::Device.new(id: 'd1', name: 'MacBook', type: 'Computer', active: true, restricted: false)
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')

    allow(source).to receive(:connect!)
    allow(source)
      .to receive_messages(
        available_devices: [device], playlists: [playlist], queue: [],
        current_playback: YouFM::Models::PlaybackState.new(
          device_name: 'MacBook', track: nil, playing: false, progress_ms: 0
        ),
        connected?: true
      )

    view_model = build_view_model
    view_model.connect_spotify

    expect(view_model.state.connected).to be(true)
    expect(view_model.state.devices).to eq([device])
    expect(view_model.state.playlists).to eq([playlist])
  end

  it 'shows the transferred active device even when Spotify returns no active playback item' do
    old_device = YouFM::Models::Device.new(id: 'd1', name: 'MacBook', type: 'Computer', active: false,
                                           restricted: false)
    target_device = YouFM::Models::Device.new(id: 'd2', name: 'iPhone', type: 'Smartphone', active: true,
                                              restricted: false)

    allow(source).to receive(:transfer_playback).with(target_device)

    view_model = build_view_model
    view_model.state.devices = [old_device, target_device]
    view_model.select_device_index(1)
    view_model.activate_selected_device

    expect(source).to have_received(:transfer_playback).with(target_device)
    expect(view_model.state.device_name).to eq('iPhone')
    expect(view_model.state.devices.map(&:active)).to eq([false, true])
    expect(view_model.state.status_message).to eq('Transferred playback to iPhone')
  end

  it 'loads selected playlist tracks into the tracks list' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [track], has_more: false }
    )

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([track])
    expect(view_model.state.tracks_title).to eq('Playlist: Daily')
  end

  it 'backs off queue refresh until Retry-After elapses after Spotify rate limiting' do
    rate_limited_error = YouFM::Services::SpotifyClient::RateLimitedError.new('Too many requests',
                                                                              retry_after_seconds: 17)
    allow(source).to receive(:queue).and_raise(rate_limited_error)

    view_model = build_view_model
    view_model.refresh_queue
    view_model.refresh_queue

    expect(source).to have_received(:queue).once
    expect(view_model.state.status_message).to eq('Queue refresh rate-limited by Spotify, retrying in 17s')
  end

  it 'switches tracks panel into playlist loading state immediately' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    call_count = 0
    allow(Thread).to receive(:new).and_wrap_original do |_original, *args, &block|
      call_count += 1
      block.call(*args) unless call_count == 1
      instance_double(Thread)
    end
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [track], has_more: false }
    )

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.tracks_title).to eq('Playlist: Daily')
    expect(view_model.state.search_results).to eq([])
    expect(view_model.state.tracks_loading_more).to be(true)
    expect(view_model.state.status_message).to eq('Loading tracks from Daily...')
  end

  it 'calls playlist loaded callback after clearing the loading flag for async first page' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    callback_loading_states = []
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [track], has_more: false }
    )

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0) { callback_loading_states << view_model.state.tracks_loading_more }

    expect(callback_loading_states).to eq([true, false])
    expect(view_model.state.search_results).to eq([track])
  end

  it 'logs Spotify playlist request failures to stdout' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')

    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_raise(
      YouFM::Services::SpotifyClient::TimeoutError,
      'Spotify request timed out'
    )

    view_model = build_view_model
    view_model.state.playlists = [playlist]

    expect { view_model.select_playlist_index(0) }.to output(
      a_string_including('[youfm] status: Playlist tracks failed: Spotify request timed out')
    ).to_stdout
  end

  it 'updates playlist loading status with elapsed seconds while async loading is active' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')
    callback = proc {}

    allow(Thread).to receive(:new).and_return(instance_double(Thread))
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(YouFM::Services::Logger).to receive(:info)

    now = Time.utc(2026, 5, 4, 10, 0, 0)
    allow(Time).to receive(:now).and_return(now, now + 12, now + 12, now + 13)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0, &callback)
    view_model.refresh_playlist_loading_status
    view_model.refresh_playlist_loading_status

    expect(view_model.state.status_message).to eq('Loading tracks from Daily... 12s')
    view_model.refresh_playlist_loading_status
    expect(view_model.state.status_message).to eq('Loading tracks from Daily... 13s')
  end

  it 'uses cached first playlist page immediately without waiting for a thread' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 10, snapshot_id: 'snap-1')
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [track], has_more: false }
    )
    allow(Thread).to receive(:new)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([track])
    expect(view_model.state.tracks_loading_more).to be(false)
    expect(Thread).not_to have_received(:new)
  end

  it 'does not keep the playlist loader visible after loading a first page with more pages' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 200, snapshot_id: 'snap-1')
    track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [track], has_more: true }
    )
    allow(Thread).to receive(:new).and_return(instance_double(Thread))

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([track])
    expect(view_model.state.tracks_loading_more).to be(false)
    expect(Thread).to have_received(:new).once
  end

  it 'uses fully cached playlist contents immediately without lazy loading' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 2, snapshot_id: 'snap-1')
    first_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track 1',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    second_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Track 2',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return([first_track, second_track])
    allow(Thread).to receive(:new)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([first_track, second_track])
    expect(view_model.state.tracks_loading_more).to be(false)
    expect(Thread).not_to have_received(:new)
  end

  it 'uses all cached playlist contents immediately and keeps loading available when cache is partial' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 200, snapshot_id: 'snap-1')
    first_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track 1',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    second_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Track 2',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return([first_track, second_track])
    allow(Thread).to receive(:new).and_return(instance_double(Thread))

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([first_track, second_track])
    expect(view_model.state.tracks_loading_more).to be(false)
    expect(Thread).to have_received(:new).once
  end

  it 'background loads remaining playlist tracks after showing cached partial contents' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 200, snapshot_id: 'snap-1')
    first_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track 1',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    second_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Track 2',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return([first_track])
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 1).and_return(
      { tracks: [second_track], has_more: false }
    )
    allow(Thread).to receive(:new).and_wrap_original do |_original, *args, &block|
      block.call(*args)
      instance_double(Thread)
    end
    stub_const('YouFM::ViewModels::PlaylistTracksLoader::BACKGROUND_PREFETCH_DELAY_SECONDS', 0)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([first_track, second_track])
    expect(view_model.state.status_message).to eq('Loaded all 2 tracks from Daily')
  end

  it 'background loads remaining playlist tracks after the first network page' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 200, snapshot_id: 'snap-1')
    first_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track 1',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    second_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Track 2',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [first_track], has_more: true }
    )
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 1).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 1).and_return(
      { tracks: [second_track], has_more: false }
    )
    allow(Thread).to receive(:new).and_wrap_original do |_original, *args, &block|
      block.call(*args)
      instance_double(Thread)
    end
    stub_const('YouFM::ViewModels::PlaylistTracksLoader::BACKGROUND_PREFETCH_DELAY_SECONDS', 0)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)

    expect(view_model.state.search_results).to eq([first_track, second_track])
    expect(view_model.state.status_message).to eq('Loaded all 2 tracks from Daily')
  end

  it 'lazy loads more playlist tracks when requested' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 200, snapshot_id: 'snap-1')
    first_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track 1',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    second_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Track 2',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [first_track], has_more: true }
    )
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 1).and_return(nil)
    allow(source).to receive(:playlist_tracks_page).with(playlist, limit: 100, offset: 1).and_return(
      { tracks: [second_track], has_more: false }
    )

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)
    view_model.load_more_playlist_tracks

    expect(view_model.state.search_results).to eq([first_track, second_track])
  end

  it 'uses cached next playlist page immediately without waiting for a thread' do
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 200, snapshot_id: 'snap-1')
    first_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track 1',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    second_track = YouFM::Models::Track.new(
      id: '2',
      title: 'Track 2',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    allow(source).to receive(:cached_playlist_tracks).with(playlist, limit: 100).and_return(nil)
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 0).and_return(
      { tracks: [first_track], has_more: true }
    )
    allow(source).to receive(:cached_playlist_tracks_page).with(playlist, limit: 100, offset: 1).and_return(
      { tracks: [second_track], has_more: false }
    )
    allow(Thread).to receive(:new)

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.select_playlist_index(0)
    view_model.load_more_playlist_tracks

    expect(view_model.state.search_results).to eq([first_track, second_track])
    expect(Thread).not_to have_received(:new)
  end

  it 'disconnects Spotify and clears UI state' do
    allow(source).to receive(:disconnect!)
    allow(source).to receive(:connected?).and_return(true, false)
    allow(source).to receive(:configured?).and_return(true)

    view_model = build_view_model
    view_model.state.search_results = [
      YouFM::Models::Track.new(id: '1', title: 'Track', artists: ['Artist'], album: 'Album', uri: 'spotify:track:1',
                               duration_ms: 1)
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
    allow(source).to receive(:play_track).and_raise(YouFM::Services::SpotifyClient::PlaybackUnavailableError,
                                                    'premium required')

    view_model = build_view_model
    view_model.state.search_results = [
      YouFM::Models::Track.new(id: '1', title: 'Track', artists: ['Artist'], album: 'Album', uri: 'spotify:track:1',
                               duration_ms: 1)
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
    allow(recommendation_generator)
      .to receive(:generate_with_seed)
      .and_return(build_recommendation(track: recommended_track, seed_track: current_track))

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.state.selected_index = 0
    view_model.play_selected

    expect(view_model.state.queue_tracks).to include(recommended_track)
    expect(view_model.state.recommendation_seed).to eq('None')
    expect(view_model.state.queue_recommendation_seeds).to eq('2' => 'Track — Artist (Взят из плейлиста: Tracks)')
    expect(recommendation_seed_store).to have_received(:save).with(
      '2',
      'Track — Artist (Взят из плейлиста: Tracks)',
      label: 'Recommended - Another Artist'
    )
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
    allow(recommendation_generator)
      .to receive(:generate_with_seed)
      .and_return(build_recommendation(track: recommended_track, seed_track: current_track))

    view_model = build_view_model
    view_model.state.search_results = [current_track]

    view_model.generate_recommendation

    expect(source).to have_received(:add_to_queue).with(recommended_track)
    expect(view_model.state.queue_tracks).to include(recommended_track)
    expect(view_model.state.status_message).to include('Added recommendation to Spotify queue')
  end

  it 'restores the cached local recommendation queue on startup' do
    allow(recommended_queue_store).to receive(:load).and_return(
      track_ids: ['cached-track'],
      tracks: [
        {
          'id' => 'cached-track',
          'name' => 'Cached Track',
          'artists' => [{ 'name' => 'Cached Artist' }],
          'album' => { 'name' => 'Cached Album' },
          'uri' => 'spotify:track:cached-track',
          'duration_ms' => 123
        }
      ],
      seeds: { 'cached-track' => 'Seed — Artist (Взят из плейлиста: Daily)' }
    )

    view_model = build_view_model

    expect(view_model.state.queue_tracks.map(&:display_label)).to eq(['Cached Track - Cached Artist'])
    expect(view_model.state.queue_recommendation_seeds).to eq(
      'cached-track' => 'Seed — Artist (Взят из плейлиста: Daily)'
    )
  end

  it 'rebuilds the local recommendation queue from Spotify queue and persisted seeds after cache loss' do
    generated_track = YouFM::Models::Track.new(
      id: 'generated-track',
      title: 'Generated',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:generated-track',
      duration_ms: 1
    )
    allow(source).to receive_messages(
      available_devices: [],
      playlists: [],
      queue: [generated_track],
      current_playback: YouFM::Models::PlaybackState.new(
        device_name: nil,
        track: nil,
        playing: false,
        progress_ms: 0
      )
    )
    allow(recommended_queue_store).to receive(:load).and_return(track_ids: [], tracks: [], seeds: {})
    allow(recommendation_seed_store).to receive(:existing_for).with(['generated-track']).and_return(
      'generated-track' => 'Seed — Artist (Взят из плейлиста: Daily)'
    )

    view_model = build_view_model
    view_model.refresh_library

    expect(view_model.state.queue_tracks).to eq([generated_track])
    expect(view_model.state.queue_recommendation_seeds).to eq(
      'generated-track' => 'Seed — Artist (Взят из плейлиста: Daily)'
    )
  end

  it 'persists the local recommendation queue after adding a recommendation' do
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
    allow(recommendation_generator)
      .to receive(:generate_with_seed)
      .and_return(build_recommendation(track: recommended_track, seed_track: current_track))

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.generate_recommendation

    expect(recommended_queue_store).to have_received(:save).with(
      track_ids: ['2'],
      tracks: [recommended_track],
      seeds: { '2' => 'Track — Artist (Взят из плейлиста: Tracks)' }
    )
  end

  it 'keeps generating recommendations until the local queue reaches the configured minimum' do
    current_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    first_recommendation = YouFM::Models::Track.new(
      id: '2',
      title: 'First Recommended',
      artists: ['Another Artist'],
      album: 'Album 2',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    second_recommendation = YouFM::Models::Track.new(
      id: '3',
      title: 'Second Recommended',
      artists: ['Another Artist'],
      album: 'Album 3',
      uri: 'spotify:track:3',
      duration_ms: 1
    )
    worker_blocks = []
    allow(Thread).to receive(:new) do |_args, &block|
      worker_blocks << block
      instance_double(Thread, alive?: true)
    end
    allow(source).to receive(:add_to_queue)
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: first_recommendation, seed_track: current_track),
      build_recommendation(track: second_recommendation, seed_track: current_track)
    )

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.update_minimum_recommended_queue_size('2')

    view_model.generate_recommendation
    worker_blocks.shift.call

    expect(source).to have_received(:add_to_queue).with(first_recommendation)
    expect(source).to have_received(:add_to_queue).with(second_recommendation)
    expect(view_model.state.queue_tracks).to eq([first_recommendation, second_recommendation])
  end

  it 'can schedule a generated recommendation asynchronously' do
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
    allow(recommendation_generator)
      .to receive(:generate_with_seed)
      .and_return(build_recommendation(track: recommended_track, seed_track: current_track))

    view_model = build_view_model
    view_model.state.search_results = [current_track]

    view_model.generate_recommendation_async

    expect(source).to have_received(:add_to_queue).with(recommended_track)
    expect(view_model.state.queue_tracks).to include(recommended_track)
    expect(view_model.state.status_message).to include('Added recommendation to Spotify queue')
  end

  it 'does not show arbitrary Spotify queue tracks as local recommendations' do
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

    allow(source).to receive_messages(
      current_playback: YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: old_track, playing: true,
                                                         progress_ms: 0), queue: [next_track]
    )
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(nil)

    view_model = build_view_model
    view_model.state.search_results = [old_track]

    view_model.refresh_playback
    view_model.refresh_queue

    expect(view_model.state.queue_tracks).to eq([])
  end

  it 'shows only recommendations that are still present in the Spotify queue using Spotify order' do
    current_track = YouFM::Models::Track.new(
      id: '1',
      title: 'Track',
      artists: ['Artist'],
      album: 'Album',
      uri: 'spotify:track:1',
      duration_ms: 1
    )
    first_recommendation = YouFM::Models::Track.new(
      id: '2',
      title: 'First Recommendation',
      artists: ['Another Artist'],
      album: 'Album 2',
      uri: 'spotify:track:2',
      duration_ms: 1
    )
    second_recommendation = YouFM::Models::Track.new(
      id: '3',
      title: 'Second Recommendation',
      artists: ['Another Artist'],
      album: 'Album 3',
      uri: 'spotify:track:3',
      duration_ms: 1
    )
    spotify_next_up = YouFM::Models::Track.new(
      id: 'spotify-next',
      title: 'Spotify Next',
      artists: ['Spotify Artist'],
      album: 'Spotify Album',
      uri: 'spotify:track:spotify-next',
      duration_ms: 1
    )

    allow(source).to receive(:add_to_queue).with(first_recommendation)
    allow(source).to receive(:add_to_queue).with(second_recommendation)
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: first_recommendation, seed_track: current_track),
      build_recommendation(track: second_recommendation, seed_track: current_track)
    )

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.generate_recommendation
    view_model.generate_recommendation

    allow(source).to receive(:queue).and_return([spotify_next_up, first_recommendation, second_recommendation])
    view_model.refresh_queue

    expect(view_model.state.queue_tracks).to eq([first_recommendation, second_recommendation])
    expect(view_model.state.queue_recommendation_seeds.keys).to eq(%w[2 3])
    expect(recommended_queue_store).to have_received(:save).with(
      track_ids: %w[2 3],
      tracks: [first_recommendation, second_recommendation],
      seeds: {
        '2' => 'Track — Artist (Взят из плейлиста: Tracks)',
        '3' => 'Track — Artist (Взят из плейлиста: Tracks)'
      }
    ).at_least(:once)
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
    playlist = YouFM::Models::Playlist.new(id: 'p1', name: 'Daily', uri: 'spotify:playlist:1', owner_name: 'me',
                                           tracks_total: 2, snapshot_id: 'snap-1')
    allow(source).to receive(:add_to_queue).with(recommended_track)
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      nil,
      build_recommendation(track: recommended_track, seed_track: next_track)
    )

    view_model = build_view_model
    view_model.state.playlists = [playlist]
    view_model.state.selected_playlist_index = 0
    view_model.state.search_results = [current_track, next_track]

    view_model.refresh_playback
    view_model.refresh_playback

    expect(source).to have_received(:add_to_queue).with(recommended_track).once
    expect(view_model.state.queue_tracks).to include(recommended_track)
    expect(view_model.state.recommendation_seed).to eq('None')
    expect(view_model.state.queue_recommendation_seeds).to eq('3' => 'Next Track — Artist (Взят из плейлиста: Daily)')
  end

  it 'shows the recommendation seed for the selected queued recommendation' do
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
    allow(recommendation_generator)
      .to receive(:generate_with_seed)
      .and_return(build_recommendation(track: recommended_track, seed_track: current_track))

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.state.selected_index = 0
    view_model.play_selected
    view_model.select_queue_index(0)

    expect(view_model.state.selected_queue_recommendation_seed).to eq('Track — Artist (Взят из плейлиста: Tracks)')
  end

  it 'shows a persisted recommendation seed for the current playback track' do
    recommended_track = YouFM::Models::Track.new(
      id: 'recommended',
      title: 'Recommended',
      artists: ['Another Artist'],
      album: 'Album 2',
      uri: 'spotify:track:recommended',
      duration_ms: 1
    )
    seed_label = 'The Great Undressing — Jenny Hval (Взят из плейлиста: Vibed)'

    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: recommended_track, playing: true, progress_ms: 0)
    )
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(nil)
    allow(recommendation_seed_store).to receive(:fetch).with('recommended').and_return(seed_label)

    view_model = build_view_model
    view_model.state.search_results = [recommended_track]
    view_model.refresh_playback

    expect(view_model.state.now_playing).to eq('Playing: Recommended - Another Artist')
    expect(view_model.state.recommendation_seed).to eq(seed_label)
  end

  it 'promotes a local queued recommendation seed when Spotify starts playing that track' do
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
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: recommended_track, seed_track: current_track),
      nil
    )
    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: recommended_track, playing: true, progress_ms: 0)
    )

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.state.selected_index = 0
    view_model.play_selected
    allow(recommendation_generator).to receive(:generate_with_seed) do
      expect(view_model.state.recommendation_seed).to eq('Track — Artist (Взят из плейлиста: Tracks)')
      nil
    end
    view_model.refresh_playback

    expect(view_model.state.queue_tracks).to eq([])
    expect(view_model.state.recommendation_seed).to eq('Track — Artist (Взят из плейлиста: Tracks)')
  end

  it 'does not show a selected queued recommendation seed as the now playing seed' do
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
    allow(recommendation_generator)
      .to receive(:generate_with_seed)
      .and_return(build_recommendation(track: recommended_track, seed_track: current_track))

    allow(source).to receive(:current_playback).and_return(
      YouFM::Models::PlaybackState.new(device_name: 'MacBook', track: current_track, playing: true, progress_ms: 0)
    )

    view_model = build_view_model
    view_model.state.search_results = [current_track]
    view_model.state.selected_index = 0
    view_model.play_selected
    view_model.select_queue_index(0)
    view_model.refresh_playback

    expect(view_model.state.selected_queue_recommendation_seed).to eq('Track — Artist (Взят из плейлиста: Tracks)')
    expect(view_model.state.recommendation_seed).to eq('None')
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
    allow(recommendation_generator).to receive(:generate_with_seed).and_return(nil)

    view_model = build_view_model
    view_model.state.search_results = [current_track, next_track]

    view_model.refresh_playback
    view_model.refresh_playback

    expect(view_model.state.status_message)
      .to eq('Auto-recommendation not added: Last.fm/Spotify did not return a suitable track')
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
