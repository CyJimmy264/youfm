# frozen_string_literal: true

module YouFM
  module Services
    module MusicSources
      class SpotifySource
        def initialize(client:)
          @client = client
        end

        def name = 'Spotify'

        def configured?
          client.configured?
        end

        def connected?
          client.connected?
        end

        def resumable_session?
          client.resumable_session?
        end

        def connect!
          client.connect!
        end

        def disconnect!
          client.disconnect!
        end

        def search_tracks(query)
          client.search_tracks(query)
        end

        def available_devices
          client.available_devices
        end

        def current_playback
          client.current_playback
        end

        def queue
          client.queue
        end

        def playlists
          client.current_user_playlists
        end

        def playlist_tracks(playlist)
          client.playlist_tracks(playlist.id, snapshot_id: playlist.snapshot_id)
        end

        def playlist_tracks_page(playlist, limit:, offset:)
          client.playlist_tracks_page(playlist.id, limit:, offset:, snapshot_id: playlist.snapshot_id)
        end

        def cached_playlist_tracks_page(playlist, limit:, offset:)
          client.cached_playlist_tracks_page(playlist.id, limit:, offset:, snapshot_id: playlist.snapshot_id)
        end

        def cached_playlist_tracks(playlist, limit:)
          client.cached_playlist_tracks(playlist.id, limit:, snapshot_id: playlist.snapshot_id)
        end

        def play_track(track)
          client.play_track(track.uri)
        end

        def add_to_queue(track)
          client.add_to_queue(track.uri)
        end

        def play_playlist(playlist, device_id: nil)
          client.play_playlist(playlist.uri, device_id:)
        end

        def transfer_playback(device)
          client.transfer_playback(device.id)
        end

        def pause
          client.pause
        end

        def resume
          client.resume
        end

        def skip_to_next
          client.skip_to_next
        end

        private

        attr_reader :client
      end
    end
  end
end
