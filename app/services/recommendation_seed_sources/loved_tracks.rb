# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationSeedSources
      class LovedTracks < UserLibraryTracksBase
        private

        def fetch_page(page:)
          lastfm_client.get_loved_tracks(page:, limit: TRACKS_PAGE_SIZE)
        end

        def fetch_total_pages
          lastfm_client.loved_tracks_total_pages(per_page: TRACKS_PAGE_SIZE)
        end

        def source_name
          'loved tracks'
        end

        def listened_at(library_track)
          library_track.loved_at
        end
      end
    end
  end
end
