# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationStrategies
      class UserLibraryTracksBase
        TRACKS_PAGE_SIZE = 10

        def initialize(lastfm_client:, matcher:, random:)
          @lastfm_client = lastfm_client
          @matcher = matcher
          @random = random
        end

        def generate(seed_track:, blocked_track_ids:, playlist_name:)
          first_page = fetch_page(page: 1)
          total_pages = [first_page.total_pages, 1].max
          selected_page = total_pages == 1 ? first_page : fetch_page(page: random.rand(total_pages) + 1)

          selected_page.tracks.shuffle.each do |library_track|
            candidate = matcher.spotify_track_candidate_for(
              artist_name: library_track.artist_name,
              track_name: library_track.name,
              blocked_track_ids: blocked_track_ids
            )
            next unless candidate

            log_recommendation(
              seed_track,
              library_track,
              candidate,
              playlist_name,
              page_info: "#{selected_page.page}/#{total_pages}"
            )
            return RecommendationGenerator::Recommendation.new(
              track: candidate,
              seed_track: nil,
              seed_label: seed_label_for(library_track)
            )
          end

          nil
        end

        private

        attr_reader :lastfm_client, :matcher, :random

        def fetch_page(page:)
          raise NotImplementedError
        end

        def source_name
          raise NotImplementedError
        end

        def listened_at(_library_track)
          nil
        end

        def log_recommendation(seed_track, library_track, candidate, playlist_name, page_info:)
          Services::Logger.info(
            "[youfm] recommendation generated: strategy=#{strategy_name} " \
            "playlist=#{playlist_name || 'unknown'} seed=#{seed_track&.display_label.inspect} " \
            "lastfm_library=#{library_track.name.inspect} artist=#{library_track.artist_name.inspect} " \
            "page=#{page_info} result=#{candidate.display_label.inspect}"
          )
        end

        def seed_label_for(library_track)
          label = "#{library_track.name} — #{library_track.artist_name}"
          timestamp = format_timestamp(listened_at(library_track))
          return "#{label} (Взят из библиотеки Last.fm #{source_name})" if timestamp.nil?

          "#{label} (Взят из библиотеки Last.fm #{source_name}; слушалось: #{timestamp})"
        end

        def format_timestamp(value)
          timestamp = Integer(value, exception: false)
          return nil unless timestamp

          Time.at(timestamp).utc.strftime('%Y-%m-%d %H:%M:%S UTC')
        end

        def strategy_name
          self.class.name.split('::').last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end
      end
    end
  end
end
