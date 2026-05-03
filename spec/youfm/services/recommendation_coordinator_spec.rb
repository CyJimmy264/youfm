# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::RecommendationCoordinator do
  let(:generator) { instance_double(YouFM::Services::RecommendationGenerator, similar_artist_pool_limit: 200) }
  let(:source) { instance_double(YouFM::Services::MusicSources::SpotifySource) }

  def build_track(id, title = "Track #{id}")
    YouFM::Models::Track.new(
      id: id,
      title: title,
      artists: ['Artist'],
      album: 'Album',
      uri: "spotify:track:#{id}",
      duration_ms: 1
    )
  end

  def build_coordinator
    described_class.new(recommendation_generator: generator, source: source)
  end

  def enqueue_context(overrides = {})
    updates = []
    appended = []
    {
      seed_tracks: [build_track('seed')],
      excluded_track_ids: [],
      playlist_name: 'Daily',
      queue_tracks: [],
      trigger: :manual,
      append_track: ->(track) { appended << track },
      update_status: ->(message) { updates << message }
    }.merge(overrides).merge(updates: updates, appended: appended)
  end

  it 'adds a generated recommendation to Spotify queue and local queue' do
    recommended_track = build_track('recommended', 'Recommended')
    allow(generator).to receive(:generate_from_playlist).and_return(recommended_track)
    allow(source).to receive(:add_to_queue).with(recommended_track)

    coordinator = build_coordinator
    context = enqueue_context
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Added recommendation to Spotify queue: Recommended - Artist')
    expect(source).to have_received(:add_to_queue).with(recommended_track)
    expect(context[:appended]).to eq([recommended_track])
    expect(context[:updates]).to eq(['Added recommendation to Spotify queue: Recommended - Artist'])
  end

  it 'does not add a duplicate recommendation' do
    recommended_track = build_track('recommended', 'Recommended')
    allow(generator).to receive(:generate_from_playlist).and_return(recommended_track)
    allow(source).to receive(:add_to_queue)

    coordinator = build_coordinator
    context = enqueue_context(queue_tracks: [recommended_track])
    result = coordinator.enqueue(**context.except(:updates, :appended))

    expect(result).to eq('Recommendation skipped: the candidate is already in the queue')
    expect(source).not_to have_received(:add_to_queue)
    expect(context[:appended]).to eq([])
  end

  it 'skips concurrent async recommendations' do
    allow(Thread).to receive(:new).and_return(instance_double(Thread))
    allow(generator).to receive(:generate_from_playlist)

    coordinator = build_coordinator
    context = enqueue_context
    coordinator.enqueue_async(**context.except(:updates, :appended))
    coordinator.enqueue_async(**context.except(:updates, :appended))

    expect(Thread).to have_received(:new).once
  end
end
