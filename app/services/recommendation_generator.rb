# frozen_string_literal: true

require 'set'

module YouFM
  module Services
    class RecommendationGenerator
      SIMILAR_ARTIST_WINDOW_SIZE = 10
      TOP_TRACK_WINDOW_SIZE = 7

      def initialize(lastfm_client:, spotify_client:)
        @lastfm_client = lastfm_client
        @spotify_client = spotify_client
      end

      def generate_from_playlist(seed_tracks, excluded_track_ids: [], playlist_name: nil)
        return nil if seed_tracks.empty?

        blocked_track_ids = excluded_track_ids.map(&:to_s).reject(&:empty?).to_set

        seed_tracks.shuffle.each do |seed_track|
          artist_name = seed_track.artists.first
          next unless artist_name

          similar_artists = @lastfm_client.get_similar_artists(artist_name)
          next if similar_artists.empty?

          similar_artists_window(similar_artists).each do |similar_artist|
            top_tracks = @lastfm_client.get_top_tracks(similar_artist.name, period: '12month', limit: 20)
            next if top_tracks.empty?

            top_tracks.first(TOP_TRACK_WINDOW_SIZE).shuffle.each do |top_track|
              query = "#{top_track.name} artist:#{similar_artist.name}"
              spotify_tracks = @spotify_client.search_tracks(query, limit: 3)
              candidate = spotify_tracks.find { |track| !blocked_track_ids.include?(track.id.to_s) }
              if candidate
                puts "[youfm] recommendation generated: playlist=#{playlist_name || 'unknown'} seed=#{seed_track.display_label.inspect} result=#{candidate.display_label.inspect}"
                return candidate
              end
            end
          end
        end

        nil
      rescue LastfmClient::Error => e
        warn "Last.fm API error during recommendation: #{e.message}"
        nil
      rescue SpotifyClient::Error => e
        warn "Spotify API error during recommendation: #{e.message}"
        nil
      end

      private

      def similar_artists_window(similar_artists)
        window_size = [SIMILAR_ARTIST_WINDOW_SIZE, similar_artists.length].min
        offset = rand(similar_artists.length)
        window = similar_artists.rotate(offset).first(window_size)
        puts "[youfm] recommendation similar artists: total=#{similar_artists.length} offset=#{offset} window=#{window.map(&:name).join(' | ')}"
        window
      end
    end
  end
end
