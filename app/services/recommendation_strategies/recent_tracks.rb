# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationStrategies
      class RecentTracks
        RECENT_TRACKS_PAGE_SIZE = 10

        def initialize(lastfm_client:, matcher:, random:)
          @lastfm_client = lastfm_client
          @matcher = matcher
          @random = random
        end

        def generate(seed_track:, blocked_track_ids:, playlist_name:)
          first_page = lastfm_client.get_recent_tracks(page: 1, limit: RECENT_TRACKS_PAGE_SIZE)
          total_pages = [first_page.total_pages, 1].max
          selected_page =
            if total_pages == 1
              first_page
            else
              lastfm_client.get_recent_tracks(page: random.rand(total_pages) + 1, limit: RECENT_TRACKS_PAGE_SIZE)
            end

          selected_page.tracks.shuffle.each do |recent_track|
            candidate = matcher.spotify_track_candidate_for(
              artist_name: recent_track.artist_name,
              track_name: recent_track.name,
              blocked_track_ids: blocked_track_ids
            )
            next unless candidate

            log_recommendation(
              seed_track,
              recent_track,
              candidate,
              playlist_name,
              page_info: "#{selected_page.page}/#{total_pages}"
            )
            return RecommendationGenerator::Recommendation.new(
              track: candidate,
              seed_track: nil,
              seed_label: seed_label_for(recent_track)
            )
          end

          nil
        end

        private

        attr_reader :lastfm_client, :matcher, :random

        def log_recommendation(seed_track, recent_track, candidate, playlist_name, page_info:)
          Services::Logger.info(
            '[youfm] recommendation generated: strategy=recent_tracks ' \
            "playlist=#{playlist_name || 'unknown'} seed=#{seed_track&.display_label.inspect} " \
            "lastfm_recent=#{recent_track.name.inspect} artist=#{recent_track.artist_name.inspect} " \
            "page=#{page_info} result=#{candidate.display_label.inspect}"
          )
        end

        def seed_label_for(recent_track)
          label = "#{recent_track.name} — #{recent_track.artist_name}"
          played_at = format_played_at(recent_track.played_at)
          return label if played_at.nil?

          "#{label} (Взят из библиотеки Last.fm recent tracks; слушалось: #{played_at})"
        end

        def format_played_at(value)
          timestamp = Integer(value, exception: false)
          return nil unless timestamp

          Time.at(timestamp).utc.strftime('%Y-%m-%d %H:%M:%S UTC')
        end
      end
    end
  end
end
