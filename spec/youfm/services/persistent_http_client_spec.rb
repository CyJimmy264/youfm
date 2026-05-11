# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::PersistentHttpClient do
  def nil_multiplication_error
    nil * 1
  rescue NoMethodError => e
    e
  end

  it 'returns HTTP error status responses without raising transport errors' do
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr.fetch(1)
    thread = Thread.new do
      socket = server.accept
      socket.gets
      loop do
        line = socket.gets
        break if line.nil? || line == "\r\n"
      end
      socket.write(
        "HTTP/1.1 429 Too Many Requests\r\n" \
        "Retry-After: 17\r\n" \
        "Content-Length: 2\r\n" \
        "Connection: close\r\n\r\n{}"
      )
      socket.close
    end

    client = described_class.new(open_timeout: 1, read_timeout: 1)
    response = client.request(YouFM::Services::HttpRequest.get(URI("http://127.0.0.1:#{port}/test")))

    expect(response.code).to eq('429')
    expect(response['Retry-After']).to eq('17')
    expect(response.body).to eq('{}')
  ensure
    thread&.kill
    server&.close
  end

  it 'retries transient nil multiplication failures from the HTTP layer' do
    response = instance_double(HTTPX::Response, status: 200, headers: {}, body: '{}')
    session = instance_double(HTTPX::Session)
    calls = 0
    allow(session).to receive(:request) do
      calls += 1
      raise nil_multiplication_error if calls == 1

      response
    end
    client = described_class.new(open_timeout: 1, read_timeout: 1)
    client.instance_variable_set(:@session, session)

    result = client.request(YouFM::Services::HttpRequest.get(URI('https://api.spotify.test/v1/me/player')))

    expect(result.code).to eq('200')
    expect(session).to have_received(:request).twice
  end

  it 'converts repeated nil multiplication failures into transport errors' do
    session = instance_double(HTTPX::Session)
    allow(session).to receive(:request).and_raise(nil_multiplication_error)
    client = described_class.new(open_timeout: 1, read_timeout: 1)
    client.instance_variable_set(:@session, session)

    expect do
      client.request(YouFM::Services::HttpRequest.get(URI('https://api.spotify.test/v1/me/player')))
    end.to raise_error(HTTPX::ConnectionError)
    expect(session).to have_received(:request).exactly(3).times
  end
end
