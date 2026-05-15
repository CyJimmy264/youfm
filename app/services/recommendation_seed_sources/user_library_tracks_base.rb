# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationSeedSources
      class UserLibraryTracksBase
        TRACKS_PAGE_SIZE = 10
        SeedCandidate = Struct.new(:track, :seed_label, :source_page, keyword_init: true)

        def initialize(lastfm_client:, random:)
          @lastfm_client = lastfm_client
          @random = random
        end

        def fetch(**)
          total_pages = [fetch_total_pages, 1].max
          selected_page = fetch_page(page: random.rand(total_pages) + 1)
          page_info = "#{selected_page.page}/#{total_pages}"
          selected_page.tracks.shuffle(random: random).map do |library_track|
            SeedCandidate.new(
              track: build_seed_track(library_track),
              seed_label: seed_label_for(library_track),
              source_page: page_info
            )
          end
        end

        private

        attr_reader :lastfm_client, :random

        def fetch_page(page:)
          raise NotImplementedError
        end

        def fetch_total_pages
          raise NotImplementedError
        end

        def source_name
          raise NotImplementedError
        end

        def listened_at(_library_track)
          nil
        end

        def build_seed_track(library_track)
          Models::Track.new(
            id: "lastfm:#{source_name}:#{library_track.artist_name}:#{library_track.name}",
            title: library_track.name,
            artists: [library_track.artist_name],
            album: library_track.album_name.to_s,
            uri: nil,
            duration_ms: 0,
            explicit: false
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
      end
    end
  end
end
