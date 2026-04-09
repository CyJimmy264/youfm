# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Application do
  around do |example|
    original_container = described_class.instance_variable_get(:@container)
    original_qt_app = described_class.instance_variable_get(:@qt_app)

    described_class.instance_variable_set(:@container, nil)
    described_class.instance_variable_set(:@qt_app, nil)

    example.run
  ensure
    described_class.instance_variable_set(:@container, original_container)
    described_class.instance_variable_set(:@qt_app, original_qt_app)
  end

  it 'memoizes container instance' do
    container = instance_double(YouFM::Container)
    allow(YouFM::Container).to receive(:new).and_return(container)

    expect(described_class.container).to equal(container)
    expect(described_class.container).to equal(container)
    expect(YouFM::Container).to have_received(:new).once
  end

  it 'keeps qt_app nil when QApplication boot raises' do
    allow(QApplication).to receive(:new).and_raise(StandardError, 'qt init failed')

    described_class.setup_qt

    expect(described_class.qt_app).to be_nil
  end
end
