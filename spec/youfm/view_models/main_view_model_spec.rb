# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::ViewModels::MainViewModel do
  let(:source) do
    instance_double(
      YouFM::Services::MusicSources::SpotifySource,
      name: 'Spotify',
      configured?: true
    )
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

    view_model = described_class.new(source: source)
    view_model.search('Track')

    expect(view_model.state.search_results).to eq([track])
    expect(view_model.state.selected_index).to eq(0)
  end

  it 'toggles playback using source pause and resume' do
    allow(source).to receive(:pause)
    allow(source).to receive(:resume)

    view_model = described_class.new(source: source)
    view_model.state.playing = true
    view_model.toggle_playback
    expect(source).to have_received(:pause)

    view_model.toggle_playback
    expect(source).to have_received(:resume)
  end
end
