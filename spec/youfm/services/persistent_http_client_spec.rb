# frozen_string_literal: true

require 'spec_helper'

RSpec.describe YouFM::Services::PersistentHttpClient do
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
end
