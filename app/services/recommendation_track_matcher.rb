# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationTrackMatcher
      def initialize(spotify_client:, exclude_explicit: true, title_blacklist: [])
        @spotify_client = spotify_client
        @exclude_explicit = exclude_explicit
        self.title_blacklist = title_blacklist
      end

      attr_accessor :exclude_explicit
      attr_reader :title_blacklist

      def spotify_track_candidate_for(artist_name:, track_name:, blocked_track_ids:)
        query = "#{track_name} artist:#{artist_name}"
        spotify_tracks = spotify_client.search_tracks(query, limit: 10)
        candidates = spotify_tracks.reject { |track| track_rejected?(track, blocked_track_ids) }
        scored_candidates = candidates.filter_map do |track|
          score = spotify_track_match_score(track, generated_artist_name: artist_name, generated_title: track_name)
          [track, score] if score
        end

        scored_candidates.max_by { |_track, score| score }&.first
      end

      def title_blacklist=(lines)
        @title_blacklist = Array(lines).map { |line| normalize_text(line) }.reject(&:empty?).uniq
      end

      def track_allowed?(track, blocked_track_ids: [])
        !track_rejected?(track, blocked_track_ids)
      end

      private

      attr_reader :spotify_client

      def track_rejected?(track, blocked_track_ids)
        blocked_track_ids.include?(track.id.to_s) ||
          (exclude_explicit && track.explicit) ||
          title_blacklisted?(track.title)
      end

      def title_blacklisted?(title)
        normalized_title = normalize_text(title)
        title_blacklist.any? { |pattern| normalized_title.include?(pattern) }
      end

      def spotify_track_match_score(track, generated_artist_name:, generated_title:)
        spotify_artist = normalize_text(track.artists.first)
        spotify_title = normalize_text(track.title)
        artist_name = normalize_text(generated_artist_name)
        title = normalize_text(generated_title)

        return unless compatible_text?(spotify_artist, artist_name) && compatible_text?(spotify_title, title)

        [
          query_coverage_score(spotify_title, title),
          query_coverage_score(spotify_artist, artist_name),
          exact_or_prefix_bonus(spotify_title, title),
          richness_score(spotify_artist),
          richness_score(spotify_title)
        ]
      end

      def compatible_text?(left, right)
        left.include?(right) || right.include?(left)
      end

      def query_coverage_score(candidate, query)
        candidate_tokens = candidate.split
        query_tokens = query.split
        return 0 if candidate_tokens.empty? || query_tokens.empty?

        ((candidate_tokens & query_tokens).length / query_tokens.length.to_f)
      end

      def exact_or_prefix_bonus(left, right)
        return 2 if left == right
        return 1 if left.start_with?(right) || right.start_with?(left)

        0
      end

      def richness_score(value)
        value.split.length
      end

      def normalize_text(value)
        value.to_s
             .unicode_normalize(:nfkd)
             .gsub(/\p{Mn}+/, '')
             .downcase
             .gsub(/(remastered(\s\d+)*|the)/, ' ')
             .gsub(/[^a-z0-9]+/, ' ')
             .strip
      end
    end
  end
end
