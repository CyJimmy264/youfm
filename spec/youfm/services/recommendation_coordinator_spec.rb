# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::RecommendationCoordinator do
  let(:generator) do
    instance_double(
      YouFM::Services::RecommendationGenerator,
      similar_artist_pool_limit: 200,
      exclude_explicit?: true,
      title_blacklist: []
    )
  end
  let(:source) { instance_double(YouFM::Services::MusicSources::SpotifySource) }
  let(:seed_store) { instance_double(YouFM::Services::RecommendationSeedStore, save: nil) }
  let(:spotify_client) { instance_double(YouFM::Services::SpotifyClient) }

  before do
    allow(YouFM::Services::Logger).to receive(:info)
    allow(YouFM::Services::Logger).to receive(:warn)
    allow(generator).to receive(:supports_seedless_generation?).and_return(false)
  end

  def build_track(id, title = "Track #{id}", uri: "spotify:track:#{id}")
    YouFM::Models::Track.new(
      id: id,
      title: title,
      artists: ['Artist'],
      album: 'Album',
      uri: uri,
      duration_ms: 1
    )
  end

  def build_recommendation(track:, seed_track:)
    YouFM::Services::RecommendationGenerator::Recommendation.new(track: track, seed_track: seed_track)
  end

  def build_coordinator
    described_class.new(
      recommendation_generator: generator,
      source: source,
      seed_store: seed_store,
      spotify_client: spotify_client
    )
  end

  def enqueue_context(overrides = {})
    updates = []
    appended = []
    {
      seed_tracks: [build_track('seed', 'Track seed')],
      excluded_track_ids: [],
      playlist_name: 'Daily',
      trigger: :manual,
      append_track: ->(track, seed_label) { appended << [track, seed_label] },
      update_status: ->(message) { updates << message }
    }.merge(overrides).merge(updates: updates, appended: appended)
  end

  it 'adds a generated recommendation to Spotify queue and local queue' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(build_recommendation(track: recommended_track,
                                                                                     seed_track: seed_track))
    allow(source).to receive(:add_to_queue).with(recommended_track)

    coordinator = build_coordinator
    context = enqueue_context
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Added recommendation to Spotify queue: Recommended - Artist')
    expect(source).to have_received(:add_to_queue).with(recommended_track)
    expect(seed_store).to have_received(:save).with(
      'recommended',
      'Track seed — Artist (Взят из плейлиста: Daily)',
      label: 'Recommended - Artist'
    )
    expect(context[:appended]).to eq([[recommended_track, 'Track seed — Artist (Взят из плейлиста: Daily)']])
    expect(context[:updates]).to eq(['Added recommendation to Spotify queue: Recommended - Artist'])
    expect(YouFM::Services::Logger).to have_received(:info).with(
      include('[youfm] enqueue target: kind=generated', 'id="recommended"', 'uri="spotify:track:recommended"')
    )
  end

  it 'allows seedless strategies to run without loaded tracks' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_label_suffix = 'Взят из библиотеки Last.fm recent tracks; слушалось: 2024-03-09 16:00:00 UTC'
    seed_label = "Recent Song — Recent Artist (#{seed_label_suffix})"
    recommendation = YouFM::Services::RecommendationGenerator::Recommendation.new(
      track: recommended_track,
      seed_track: nil,
      seed_label: seed_label
    )
    allow(generator).to receive_messages(supports_seedless_generation?: true, generate_with_seed: recommendation)
    allow(source).to receive(:add_to_queue).with(recommended_track)

    coordinator = build_coordinator
    context = enqueue_context(seed_tracks: [])
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Added recommendation to Spotify queue: Recommended - Artist')
    expect(context[:appended]).to eq([[recommended_track, seed_label]])
  end

  it 'can replay the seed before the recommendation at the configured interval' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(build_recommendation(track: recommended_track,
                                                                                     seed_track: seed_track))
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    coordinator.replay_seed_before_recommendation = true
    coordinator.seed_replay_interval = 1
    context = enqueue_context
    coordinator.enqueue(**context.except(:updates, :appended))

    expect(source).to have_received(:add_to_queue).ordered.with(seed_track)
    expect(source).to have_received(:add_to_queue).ordered.with(recommended_track)
    expect(context[:appended]).to eq([
                                       [seed_track, 'Track seed — Artist (Взят из плейлиста: Daily)'],
                                       [recommended_track, 'Track seed — Artist (Взят из плейлиста: Daily)']
                                     ])
  end

  it 'resolves seed replay through Spotify when the seed track has no uri' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed', uri: nil)
    resolved_seed_track = build_track('resolved-seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(build_recommendation(track: recommended_track,
                                                                                     seed_track: seed_track))
    allow(source).to receive(:add_to_queue)
    allow(spotify_client).to receive(:search_tracks)
      .with('Track seed artist:Artist', limit: 10)
      .and_return([resolved_seed_track])

    coordinator = build_coordinator
    coordinator.replay_seed_before_recommendation = true
    coordinator.seed_replay_interval = 1
    context = enqueue_context
    coordinator.enqueue(**context.except(:updates, :appended))

    expect(source).to have_received(:add_to_queue).ordered.with(resolved_seed_track)
    expect(source).to have_received(:add_to_queue).ordered.with(recommended_track)
    expect(context[:appended]).to eq([
                                       [resolved_seed_track, 'Track seed — Artist (Взят из плейлиста: Daily)'],
                                       [recommended_track, 'Track seed — Artist (Взят из плейлиста: Daily)']
                                     ])
    expect(YouFM::Services::Logger).to have_received(:info).with(
      include('[youfm] seed replay resolved:', 'source_id="seed"', 'resolved_id="resolved-seed"')
    )
  end

  it 'skips seed replay when Spotify cannot resolve the seed track' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed', uri: nil)
    allow(generator).to receive(:generate_with_seed).and_return(build_recommendation(track: recommended_track,
                                                                                     seed_track: seed_track))
    allow(source).to receive(:add_to_queue)
    allow(spotify_client).to receive(:search_tracks)
      .with('Track seed artist:Artist', limit: 10)
      .and_return([])

    coordinator = build_coordinator
    coordinator.replay_seed_before_recommendation = true
    coordinator.seed_replay_interval = 1
    context = enqueue_context
    coordinator.enqueue(**context.except(:updates, :appended))

    expect(source).to have_received(:add_to_queue).once.with(recommended_track)
    expect(context[:appended]).to eq([[recommended_track, 'Track seed — Artist (Взят из плейлиста: Daily)']])
    expect(YouFM::Services::Logger).to have_received(:info).with(
      include('[youfm] seed replay skipped: spotify match not found', 'id="seed"')
    )
  end

  it 'does not add a duplicate recommendation' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(build_recommendation(track: recommended_track,
                                                                                     seed_track: seed_track))
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    context = enqueue_context(excluded_track_ids: [recommended_track.id])
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Recommendation not added: the candidate is already in the queue')
    expect(source).not_to have_received(:add_to_queue)
    expect(context[:appended]).to eq([])
  end

  it 'retries when generation returns no candidate' do
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(
      nil,
      build_recommendation(track: recommended_track, seed_track: seed_track)
    )
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    context = enqueue_context
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Added recommendation to Spotify queue: Recommended - Artist')
    expect(source).to have_received(:add_to_queue).with(recommended_track)
    expect(generator).to have_received(:generate_with_seed).twice
  end

  it 'retries duplicate candidates before giving up' do
    duplicate_track = build_track('duplicate', 'Duplicate')
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: duplicate_track, seed_track: seed_track),
      build_recommendation(track: recommended_track, seed_track: seed_track)
    )
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    context = enqueue_context(excluded_track_ids: [duplicate_track.id])
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Added recommendation to Spotify queue: Recommended - Artist')
    expect(source).to have_received(:add_to_queue).with(recommended_track)
  end

  it 'queues concurrent async recommendations' do
    worker = instance_double(Thread, alive?: true)
    worker_block = nil
    allow(Thread).to receive(:new) do |_args, &block|
      worker_block = block
      worker
    end
    first_track = build_track('first', 'First')
    second_track = build_track('second', 'Second')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(
      build_recommendation(track: first_track, seed_track: seed_track),
      build_recommendation(track: second_track, seed_track: seed_track)
    )
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    context = enqueue_context
    coordinator.enqueue_async(**context.except(:updates, :appended))
    coordinator.enqueue_async(**context.except(:updates, :appended))
    worker_block.call

    expect(Thread).to have_received(:new).once
    expect(source).to have_received(:add_to_queue).with(first_track)
    expect(source).to have_received(:add_to_queue).with(second_track)
    expect(context[:appended].map(&:first)).to eq([first_track, second_track])
  end

  it 'uses current excluded track ids when an async recommendation runs later' do
    worker = instance_double(Thread, alive?: true)
    worker_block = nil
    allow(Thread).to receive(:new) do |_args, &block|
      worker_block = block
      worker
    end
    excluded_track_ids = []
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    allow(generator).to receive(:generate_with_seed).and_return(build_recommendation(track: recommended_track,
                                                                                     seed_track: seed_track))
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    context = enqueue_context(excluded_track_ids: -> { excluded_track_ids })
    coordinator.enqueue_async(**context.except(:updates, :appended))
    excluded_track_ids << recommended_track.id
    worker_block.call

    expect(source).not_to have_received(:add_to_queue)
    expect(context[:updates]).to eq(['Recommendation not added: the candidate is already in the queue'])
  end

  it 'retries transient async failures with backoff' do
    worker = instance_double(Thread, alive?: true)
    worker_block = nil
    allow(Thread).to receive(:new) do |_args, &block|
      worker_block = block
      worker
    end
    recommended_track = build_track('recommended', 'Recommended')
    seed_track = build_track('seed', 'Track seed')
    calls = 0
    allow(generator).to receive(:generate_with_seed) do
      calls += 1
      raise YouFM::Services::SpotifyClient::TimeoutError, 'Spotify request timed out' if calls == 1

      build_recommendation(track: recommended_track, seed_track: seed_track)
    end
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    allow(coordinator).to receive(:sleep).with(5)
    context = enqueue_context
    coordinator.enqueue_async(**context.except(:updates, :appended))
    worker_block.call

    expect(context[:updates]).to eq([
                                      'Recommendation failed: Spotify request timed out; retrying in 5s',
                                      'Added recommendation to Spotify queue: Recommended - Artist'
                                    ])
    expect(source).to have_received(:add_to_queue).with(recommended_track)
  end

  it 'reports non-transient async recommendation failures through status updates' do
    worker = instance_double(Thread, alive?: true)
    worker_block = nil
    allow(Thread).to receive(:new) do |_args, &block|
      worker_block = block
      worker
    end
    allow(generator).to receive(:generate_with_seed).and_raise(
      YouFM::Services::SpotifyClient::AuthenticationError,
      'Token expired'
    )

    coordinator = build_coordinator
    context = enqueue_context
    coordinator.enqueue_async(**context.except(:updates, :appended))
    worker_block.call

    expect(context[:updates]).to eq(['Recommendation failed: Token expired'])
  end
end
