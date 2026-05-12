# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationTrackMatcher
      def initialize(spotify_client:, exclude_explicit: true)
        @spotify_client = spotify_client
        @exclude_explicit = exclude_explicit
      end

      attr_accessor :exclude_explicit

      def spotify_track_candidate_for(artist_name:, track_name:, blocked_track_ids:)
        query = "#{track_name} artist:#{artist_name}"
        spotify_tracks = spotify_client.search_tracks(query, limit: 10)
        spotify_tracks.find do |track|
          next false if blocked_track_ids.include?(track.id.to_s)
          next false if exclude_explicit && track.explicit

          spotify_track_matches?(track, generated_artist_name: artist_name, generated_title: track_name)
        end
      end

      private

      attr_reader :spotify_client

      def spotify_track_matches?(track, generated_artist_name:, generated_title:)
        spotify_artist = normalize_text(track.artists.first)
        spotify_title = normalize_text(track.title)
        artist_name = normalize_text(generated_artist_name)
        title = normalize_text(generated_title)

        (spotify_artist.include?(artist_name) || artist_name.include?(spotify_artist)) &&
          (spotify_title.include?(title) || title.include?(spotify_title))
      end

      def normalize_text(value)
        value.to_s.downcase.gsub(/(remastered(\s\d+)*|the)/, ' ').gsub(/[^a-z0-9]+/, ' ').strip
      end
    end
  end
end
