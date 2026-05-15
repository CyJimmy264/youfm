# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'

RSpec.describe YouFM::Services::WebUiServer do
  let(:state) do
    YouFM::ViewModels::MainViewModel::State.new(
      now_playing: 'Playing: Track - Artist',
      recommendation_seed: 'Seed — Artist (Взят из плейлиста: Daily)',
      status_message: 'Ready',
      device_name: 'Laptop',
      tracks_title: 'Playlist: Daily',
      search_results: [
        YouFM::Models::Track.new(
          id: 't1',
          title: 'Track',
          artists: ['Artist'],
          album: 'Album',
          uri: 'spotify:track:t1',
          duration_ms: 1
        )
      ],
      devices: [
        YouFM::Models::Device.new(id: 'd1', name: 'Laptop', type: 'Computer', active: true, restricted: false),
        YouFM::Models::Device.new(id: 'd2', name: 'Phone', type: 'Smartphone', active: false, restricted: false)
      ],
      selected_device_index: 0,
      playlists: [
        YouFM::Models::Playlist.new(
          id: 'p1',
          name: 'Daily',
          uri: 'spotify:playlist:p1',
          owner_name: 'Maksim',
          tracks_total: 42,
          snapshot_id: 's1'
        ),
        YouFM::Models::Playlist.new(
          id: 'p2',
          name: 'Night',
          uri: 'spotify:playlist:p2',
          owner_name: 'Maksim',
          tracks_total: 7,
          snapshot_id: 's2'
        )
      ],
      selected_playlist_index: 0,
      playing: true
    )
  end
  let(:view_model) do
    instance_double(
      YouFM::ViewModels::MainViewModel,
      state: state,
      similar_artist_pool_limit: 200,
      minimum_recommended_queue_size: 1,
      maximum_recommended_queue_size: 25,
      recommendation_seed_source_labels: {
        current_playlist: 'Current playlist / tracks list',
        recent_tracks: 'Random recent Last.fm track'
      },
      recommendation_generator_labels: {
        raw_seed: 'Raw seed',
        artist_similar_top_tracks: 'Similar artist top tracks',
        track_similar: 'Similar tracks',
        same_artist: 'Same artist'
      },
      enabled_recommendation_seed_source_names: [:current_playlist],
      enabled_recommendation_generator_names: [:artist_similar_top_tracks],
      recommendation_generator_weights: { raw_seed: 1, artist_similar_top_tracks: 4, track_similar: 2,
                                          same_artist: 1 },
      filter_explicit_content?: true,
      replay_seed_before_recommendation?: true,
      seed_replay_interval: 4,
      toggle_playback: nil,
      skip_to_next: nil,
      generate_recommendation: nil,
      generate_recommendation_async: nil,
      update_similar_artist_pool_limit: 300,
      update_minimum_recommended_queue_size: 2,
      update_maximum_recommended_queue_size: 8,
      update_recommendation_pipeline_settings: {
        seed_sources: %i[current_playlist recent_tracks],
        generators: %i[raw_seed track_similar],
        generator_weights: { raw_seed: 2, track_similar: 5 }
      },
      update_seed_replay_settings: { enabled: true, interval: 4 },
      'filter_explicit_content=': true,
      select_device_index: nil,
      activate_selected_device: nil,
      select_playlist_index: nil,
      refresh_playback: nil,
      refresh_library: nil,
      'status=': nil,
      revision: 7,
      wait_for_revision: 7
    )
  end
  let(:settings_store) do
    instance_double(
      YouFM::Services::SettingsStore,
      write_similar_artist_pool_limit: nil,
      write_minimum_recommended_queue_size: nil,
      write_maximum_recommended_queue_size: nil,
      write_enabled_seed_source_names: nil,
      write_enabled_generator_names: nil,
      write_generator_weights: nil,
      write_exclude_explicit_recommendations: nil,
      write_replay_seed_before_recommendation: nil,
      write_seed_replay_interval: nil
    )
  end

  def build_server
    described_class.new(view_model: view_model, settings_store: settings_store)
  end

  def rack_request(server = build_server)
    Rack::MockRequest.new(server)
  end

  it 'renders playback controls and status' do
    html = build_server.send(:render_page)

    expect(html).to include('Play/Pause')
    expect(html).to include('Next')
    expect(html).to include('Generate Next')
    expect(html).to include('Artist Pool')
    expect(html).to include('Sync Library')
    expect(html).to include('Playing: Track - Artist')
  end

  it 'renders numeric settings controls' do
    html = build_server.send(:render_page)

    expect(html).to include('Artist Pool')
    expect(html).to include('Min Queue')
    expect(html).to include('Max Queue')
    expect(html).to include('minimum_queue_size')
    expect(html).to include('maximum_queue_size')
  end

  it 'renders recommendation strategy controls', :aggregate_failures do
    html = build_server.send(:render_page)

    expect(html).to include('Seed Sources')
    expect(html).to include('Generators')
    expect(html).to include('Current playlist / tracks list')
    expect(html).to include('Random recent Last.fm track')
    expect(html).to include('Raw seed')
    expect(html).to include('Similar artist top tracks')
    expect(html).to include('Similar tracks')
    expect(html).to include('Same artist')
    expect(html).to include('Exclude explicit content')
    expect(html).to include('Queue Modifiers')
    expect(html).to include('Replay seed every N generated tracks')
    expect(html).to include('Ignored for Raw seed')
    expect(html).to include('seed_source_names[]')
    expect(html).to include('generator_names[]')
    expect(html).to include('generator_weights[raw_seed]')
  end

  it 'renders device picker controls' do
    html = build_server.send(:render_page)

    expect(html).to include('Use Device')
    expect(html).to include('Laptop · Computer · active')
  end

  it 'renders playlist seed controls' do
    html = build_server.send(:render_page)

    expect(html).to include('Seed Playlist')
    expect(html).to include('Daily · Maksim · 42 tracks')
    expect(html).to include('Playlist: Daily · 1 seed tracks')
  end

  it 'renders an async recent log panel without reading log lines' do
    allow(YouFM::Services::LogFile).to receive(:tail)
    allow(YouFM::Services::LogFile).to receive(:path).and_return('/tmp/youfm.log')

    html = build_server.send(:render_page)

    expect(html).to include('Recent Log')
    expect(html).to include('id="recent_log"')
    expect(html).to include('/log')
    expect(html).to include('/tmp/youfm.log')
    expect(YouFM::Services::LogFile).not_to have_received(:tail)
  end

  it 'serves recent log lines as json' do
    allow(YouFM::Services::LogFile).to receive(:tail).with(lines: 50).and_return(['line 1', '', 'line 2'])
    allow(YouFM::Services::LogFile).to receive(:path).and_return('/tmp/youfm.log')

    response = rack_request.get('/log')

    expect(response.status).to eq(200)
    expect(response['Content-Type']).to eq('application/json; charset=utf-8')
    expect(JSON.parse(response.body)).to include('path' => '/tmp/youfm.log', 'lines' => ['line 1', 'line 2'])
  end

  it 'serves recent log lines as an event stream' do
    allow(YouFM::Services::LogFile).to receive(:tail).with(lines: 50).and_return(['line 1'])
    allow(YouFM::Services::LogFile).to receive(:path).and_return('/tmp/youfm.log')

    status, headers, body = build_server.call(Rack::MockRequest.env_for('/log/stream'))

    expect(status).to eq(200)
    expect(headers['Content-Type']).to eq('text/event-stream; charset=utf-8')
    event = body.next
    expect(event).to start_with("event: log\ndata: ")
    expect(event).to include('"path":"/tmp/youfm.log","lines":["line 1"]')
    expect(event).to end_with("\n\n")
  end

  it 'serves current state as json' do
    response = rack_request.get('/state')

    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to include(
      'now_playing' => 'Playing: Track - Artist',
      'recommendation_seed' => 'Seed — Artist (Взят из плейлиста: Daily)',
      'status_message' => 'Ready',
      'device_name' => 'Laptop',
      'selected_playlist_index' => 0,
      'tracks_title' => 'Playlist: Daily',
      'seed_track_count' => 1,
      'revision' => 7
    )
    expect(JSON.parse(response.body).fetch('playlists')).to include(
      'index' => 0,
      'label' => 'Daily · Maksim · 42 tracks'
    )
  end

  it 'serves current state as an event stream' do
    status, headers, body = build_server.call(Rack::MockRequest.env_for('/state/stream'))

    expect(status).to eq(200)
    expect(headers['Content-Type']).to eq('text/event-stream; charset=utf-8')
    event = body.next
    expect(event).to start_with("event: state\ndata: ")
    expect(event).to include('"now_playing":"Playing: Track - Artist"')
    expect(event).to include('"status_message":"Ready"')
    expect(event).to end_with("\n\n")
  end

  it 'runs player actions through the view model' do
    server = build_server

    server.send(:run_action, :toggle, {})
    server.send(:run_action, :next, {})
    server.send(:run_action, :generate, {})
    server.send(:run_action, :refresh, {})
    server.send(:run_action, :sync_library, {})

    expect(view_model).to have_received(:toggle_playback)
    expect(view_model).to have_received(:skip_to_next)
    expect(view_model).to have_received(:generate_recommendation_async)
    expect(view_model).to have_received(:refresh_playback)
    expect(view_model).to have_received(:refresh_library)
  end

  it 'applies and persists numeric settings' do
    server = build_server

    server.send(
      :run_action,
      :apply_numeric_settings,
      { 'pool_limit' => '300', 'minimum_queue_size' => '2', 'maximum_queue_size' => '8' }
    )

    expect(view_model).to have_received(:update_similar_artist_pool_limit).with('300')
    expect(settings_store).to have_received(:write_similar_artist_pool_limit).with(300)
    expect(view_model).to have_received(:update_minimum_recommended_queue_size).with('2')
    expect(settings_store).to have_received(:write_minimum_recommended_queue_size).with(2)
    expect(view_model).to have_received(:update_maximum_recommended_queue_size).with('8')
    expect(settings_store).to have_received(:write_maximum_recommended_queue_size).with(8)
  end

  it 'applies and persists recommendation strategies', :aggregate_failures do
    server = build_server
    allow(view_model).to receive(:filter_explicit_content=).with(false).and_return(false)
    allow(view_model).to receive(:update_seed_replay_settings).with(enabled: false, interval: '').and_return(
      enabled: false,
      interval: 4
    )

    server.send(
      :run_action,
      :apply_recommendation_strategies,
      {
        'seed_source_names' => %w[current_playlist recent_tracks],
        'generator_names' => %w[raw_seed track_similar],
        'generator_weights' => { 'raw_seed' => '2', 'track_similar' => '5' }
      }
    )

    expect(view_model).to have_received(:update_recommendation_pipeline_settings).with(
      seed_sources: %w[current_playlist recent_tracks],
      generators: %w[raw_seed track_similar],
      generator_weights: { 'raw_seed' => '2', 'track_similar' => '5' }
    )
    expect(settings_store).to have_received(:write_enabled_seed_source_names).with(%i[current_playlist recent_tracks])
    expect(settings_store).to have_received(:write_enabled_generator_names).with(%i[raw_seed track_similar])
    expect(settings_store).to have_received(:write_generator_weights).with(raw_seed: 2, track_similar: 5)
    expect(view_model).to have_received(:filter_explicit_content=).with(false)
    expect(settings_store).to have_received(:write_exclude_explicit_recommendations).with(false)
    expect(settings_store).to have_received(:write_replay_seed_before_recommendation).with(false)
    expect(settings_store).to have_received(:write_seed_replay_interval).with(4)
  end

  it 'applies and persists the explicit content filter' do
    server = build_server
    allow(view_model).to receive(:filter_explicit_content=).with(true).and_return(true)
    allow(view_model).to receive(:update_seed_replay_settings).with(enabled: false, interval: '').and_return(
      enabled: false,
      interval: 4
    )

    server.send(
      :run_action,
      :apply_recommendation_strategies,
      { 'exclude_explicit' => '1' }
    )

    expect(view_model).to have_received(:filter_explicit_content=).with(true)
    expect(settings_store).to have_received(:write_exclude_explicit_recommendations).with(true)
  end

  it 'applies and persists seed replay settings' do
    server = build_server
    allow(view_model).to receive(:filter_explicit_content=).with(false).and_return(false)
    allow(view_model).to receive(:update_seed_replay_settings).with(enabled: true, interval: '5').and_return(
      enabled: true,
      interval: 5
    )

    server.send(
      :run_action,
      :apply_recommendation_strategies,
      {
        'seed_source_names' => ['current_playlist'],
        'generator_names' => ['artist_similar_top_tracks'],
        'generator_weights' => { 'artist_similar_top_tracks' => '4' },
        'replay_seed_before_recommendation' => '1',
        'seed_replay_interval' => '5'
      }
    )

    expect(view_model).to have_received(:update_seed_replay_settings).with(enabled: true, interval: '5')
    expect(settings_store).to have_received(:write_replay_seed_before_recommendation).with(true)
    expect(settings_store).to have_received(:write_seed_replay_interval).with(5)
  end

  it 'selects and activates a device' do
    server = build_server

    server.send(:run_action, :use_device, { 'device_index' => '1' })

    expect(view_model).to have_received(:select_device_index).with(1)
    expect(view_model).to have_received(:activate_selected_device)
  end

  it 'selects a seed playlist' do
    server = build_server

    server.send(:run_action, :select_playlist, { 'playlist_index' => '1' })

    expect(view_model).to have_received(:select_playlist_index).with(1)
  end

  it 'redirects immediately after dispatching an action' do
    server = build_server
    allow(server).to receive(:start_action_worker)

    response = rack_request(server).post('/action', params: { 'name' => 'refresh' })

    expect(response.status).to eq(303)
    expect(response['Location']).to eq('/')
    expect(server.send(:action_queue).size).to eq(1)
  end

  it 'responds to ajax actions without redirecting' do
    server = build_server
    allow(server).to receive(:start_action_worker)

    response = rack_request(server).post(
      '/action',
      params: { 'name' => 'refresh' },
      'HTTP_ACCEPT' => 'application/json'
    )

    expect(response.status).to eq(202)
    expect(response['Content-Type']).to eq('application/json; charset=utf-8')
    expect(response.body).to include('Web UI action queued: Refresh')
    expect(response['Location']).to be_nil
  end

  it 'processes queued actions with a worker' do
    fake_view_model = Class.new do
      attr_reader :state, :similar_artist_pool_limit, :minimum_recommended_queue_size,
                  :maximum_recommended_queue_size, :refreshed, :statuses

      def initialize(state)
        @state = state
        @similar_artist_pool_limit = 200
        @minimum_recommended_queue_size = 1
        @maximum_recommended_queue_size = 25
        @recommendation_seed_source_labels = {}
        @recommendation_generator_labels = {}
        @enabled_recommendation_seed_source_names = []
        @enabled_recommendation_generator_names = []
        @recommendation_generator_weights = {}
        @refreshed = Queue.new
        @statuses = Queue.new
      end

      attr_reader :recommendation_seed_source_labels, :recommendation_generator_labels,
                  :enabled_recommendation_seed_source_names, :enabled_recommendation_generator_names,
                  :recommendation_generator_weights

      def status=(message)
        statuses << message
      end

      def refresh_playback
        refreshed << true
      end
    end.new(state)
    server = described_class.new(view_model: fake_view_model, settings_store: settings_store)

    server.send(:dispatch_action, 'refresh', {})
    server.send(:start_action_worker)

    expect(fake_view_model.refreshed.pop(timeout: 1)).to be(true)
    expect(fake_view_model.statuses.pop).to eq('Web UI action queued: Refresh')
    expect(fake_view_model.statuses.pop).to eq('Web UI action started: Refresh')
    server.send(:stop_action_worker)
  end
end
