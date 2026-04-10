# frozen_string_literal: true

require 'net/http'
require 'json'
require 'digest/md5'

module YouFM
  module Services
    class LastfmClient
      class Error < StandardError; end

      def initialize(api_key:, secret:, session_key: nil, base_url: 'http://ws.audioscrobbler.com/2.0/')
        @api_key = api_key
        @secret = secret
        @session_key = session_key
        @base_url = base_url
      end

      SimilarArtist = Struct.new(:name, :match, keyword_init: true)
      TopTrack = Struct.new(:name, :playcount, :listeners, keyword_init: true)

      def auth_get_token
        get({method: 'auth.getToken'})
      end

      def auth_get_session(token)
        get({method: 'auth.getSession', token: token}, signed: true)
      end

      def get_similar_artists(artist_name, limit: 10)
        body = get({method: 'artist.getSimilar', artist: artist_name, limit: limit}, signed: true)
        artists = body.dig('similarartists', 'artist') || []
        artists.map do |artist_data|
          SimilarArtist.new(
            name: artist_data['name'],
            match: artist_data['match'].to_f
          )
        end
      end

      def get_top_tracks(artist_name, limit: 10, period: '12month')
        body = get({method: 'artist.getTopTracks', artist: artist_name, limit: limit, period: period}, signed: true)
        tracks = body.dig('toptracks', 'track') || []
        tracks.map do |track_data|
          TopTrack.new(
            name: track_data['name'],
            playcount: track_data['playcount'].to_i,
            listeners: track_data['listeners'].to_i
          )
        end
      end

      private

      attr_reader :api_key, :secret, :session_key, :base_url

      def get(params = {}, signed: false)
        params.merge!(api_key: api_key, format: 'json')
        params.merge!(sk: session_key) if signed && session_key
        params.merge!(api_sig: sign(params)) if signed

        uri = build_uri(params)
        response = Net::HTTP.get_response(uri)
        handle_response(response)
      end

      def sign(params)
        params_for_signing = params.reject { |k, _v| k.to_s == 'format' }
        param_string = params_for_signing.sort.map { |k, v| "#{k}#{v}" }.join
        Digest::MD5.hexdigest(param_string + secret)
      end

      def build_uri(params = {})
        uri = URI.parse(base_url)
        uri.query = URI.encode_www_form(params)
        uri
      end

      def handle_response(response)
        code = response.code.to_i
        body = response.body.to_s
        raise Error, "Last.fm API error: #{code} #{body}" if code >= 400

        JSON.parse(body)
      end
    end
  end
end
