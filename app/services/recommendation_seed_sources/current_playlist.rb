# frozen_string_literal: true

module YouFM
  module Services
    module RecommendationSeedSources
      class CurrentPlaylist
        SeedCandidate = Struct.new(:track, :seed_label, keyword_init: true)

        def fetch(seed_tracks:, random:, **)
          Array(seed_tracks).shuffle(random: random).map do |track|
            SeedCandidate.new(track: track, seed_label: nil)
          end
        end
      end
    end
  end
end
