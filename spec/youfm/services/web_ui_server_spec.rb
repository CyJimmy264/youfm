# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::WebUiServer do
  let(:state) do
    YouFM::ViewModels::MainViewModel::State.new(
      now_playing: 'Playing: Track - Artist',
      recommendation_seed: 'Seed — Artist (Взят из плейлиста: Daily)',
      status_message: 'Ready',
      device_name: 'Laptop',
      playing: true
    )
  end
  let(:view_model) do
    instance_double(
      YouFM::ViewModels::MainViewModel,
      state: state,
      similar_artist_pool_limit: 200,
      toggle_playback: nil,
      skip_to_next: nil,
      generate_recommendation: nil,
      update_similar_artist_pool_limit: 300,
      refresh_playback: nil,
      refresh_library: nil,
      'status=': nil
    )
  end
  let(:settings_store) { instance_double(YouFM::Services::SettingsStore, write_similar_artist_pool_limit: nil) }

  def build_server
    described_class.new(view_model: view_model, settings_store: settings_store)
  end

  before do
    allow(Thread).to receive(:new).and_wrap_original do |_original, *args, &block|
      block.call(*args)
      instance_double(Thread)
    end
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

  it 'runs player actions through the view model' do
    server = build_server

    server.send(:run_action, 'toggle', {})
    server.send(:run_action, 'next', {})
    server.send(:run_action, 'generate', {})
    server.send(:run_action, 'refresh', {})
    server.send(:run_action, 'sync_library', {})

    expect(view_model).to have_received(:toggle_playback)
    expect(view_model).to have_received(:skip_to_next)
    expect(view_model).to have_received(:generate_recommendation)
    expect(view_model).to have_received(:refresh_playback)
    expect(view_model).to have_received(:refresh_library)
  end

  it 'applies and persists artist pool limit' do
    server = build_server

    server.send(:run_action, 'apply_pool', { 'pool_limit' => '300' })

    expect(view_model).to have_received(:update_similar_artist_pool_limit).with('300')
    expect(settings_store).to have_received(:write_similar_artist_pool_limit).with(300)
  end

  it 'redirects immediately after dispatching an action' do
    request = instance_double(WEBrick::HTTPRequest, request_method: 'POST', query: { 'name' => 'refresh' })
    response = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
    server = build_server

    server.send(:handle_action, request, response)

    expect(response.status).to eq(303)
    expect(response['Location']).to eq('/')
    expect(view_model).to have_received(:refresh_playback)
  end
end
