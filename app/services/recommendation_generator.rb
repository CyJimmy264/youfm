# frozen_string_literal: true

module YouFM
  module Services
    class RecommendationGenerator
      def initialize(lastfm_client:, spotify_client:)
        @lastfm_client = lastfm_client
        @spotify_client = spotify_client
      end

      def generate_from_playlist(seed_tracks)
        return nil if seed_tracks.empty?

        seed_track = seed_tracks.sample
        artist_name = seed_track.artists.first
        return nil unless artist_name

        similar_artists = @lastfm_client.get_similar_artists(artist_name, limit: 20)
        return nil if similar_artists.empty?

        similar_artist = similar_artists.sample
        top_tracks = @lastfm_client.get_top_tracks(similar_artist.name, period: '12month', limit: 20)
        return nil if top_tracks.empty?

        top_track = top_tracks.first(7).sample
        return nil unless top_track

        # Search for the recommended track on Spotify
        query = "#{top_track.name} artist:#{similar_artist.name}"
        spotify_tracks = @spotify_client.search_tracks(query, limit: 1)
        spotify_tracks.first
      rescue LastfmClient::Error => e
        warn "Last.fm API error during recommendation: #{e.message}"
        nil
      rescue SpotifyClient::Error => e
        warn "Spotify API error during recommendation: #{e.message}"
        nil
      end
    end
  end
end
