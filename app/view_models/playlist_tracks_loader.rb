# frozen_string_literal: true

module YouFM
  module ViewModels
    class PlaylistTracksLoader
      def initialize(state:, source:, page_size:, update_status:, friendly_error_message:)
        @state = state
        @source = source
        @page_size = page_size
        @update_status = update_status
        @friendly_error_message = friendly_error_message
        reset
      end

      def select(playlist, &on_loaded)
        return unless playlist

        reset
        @playlist_id = playlist.id
        state.search_query = ''
        state.search_results = []
        state.selected_index = nil
        state.tracks_title = "Playlist: #{playlist.name}"
        state.tracks_loading_more = true
        update_status.call("Loading tracks from #{playlist.name}...")
        on_loaded&.call

        return if cached_playlist_tracks_loaded?(playlist, on_loaded)

        start_tracks_async(playlist, on_loaded, loading_message: "Loading tracks from #{playlist.name}")
      end

      def load_more(playlist, &on_loaded)
        return unless can_load_more?(playlist)

        cached_page = cached_page_for(playlist)
        if cached_page
          append_page(playlist, cached_page)
          on_loaded&.call
          return
        end

        load_more_async(playlist, on_loaded)
      end

      def refresh_loading_status
        return unless @loading && @loading_started_at

        elapsed = (Time.now - @loading_started_at).floor
        return if @loading_elapsed == elapsed

        @loading_elapsed = elapsed
        update_status.call("#{@loading_label}... #{elapsed}s")
      end

      def reset
        @playlist_id = nil
        @offset = 0
        @has_more = false
        @loading = false
        @loading_label = nil
        @loading_started_at = nil
        @loading_elapsed = nil
        state.tracks_loading_more = false
      end

      private

      attr_reader :state, :source, :page_size, :update_status, :friendly_error_message

      def cached_playlist_tracks_loaded?(playlist, on_loaded)
        cached_tracks = source.cached_playlist_tracks(playlist, limit: page_size)
        if cached_tracks
          apply_cached_tracks(playlist, cached_tracks)
          state.tracks_loading_more = false
          on_loaded&.call
          return true
        end

        cached_page = source.cached_playlist_tracks_page(playlist, limit: page_size, offset: 0)
        return false unless cached_page

        apply_page(playlist, cached_page)
        state.tracks_loading_more = false
        on_loaded&.call
        true
      end

      def can_load_more?(playlist)
        playlist && @playlist_id == playlist.id && @has_more && !@loading
      end

      def cached_page_for(playlist)
        source.cached_playlist_tracks_page(playlist, limit: page_size, offset: @offset)
      end

      def load_more_async(playlist, on_loaded)
        @loading = true
        start_loading_status!("Loading more tracks from #{playlist.name}")
        state.tracks_loading_more = true
        Thread.new do
          page = source.playlist_tracks_page(playlist, limit: page_size, offset: @offset)
          append_page(playlist, page)
        rescue Services::SpotifyClient::AuthenticationError
          update_status.call('Connect Spotify first')
        rescue StandardError => e
          update_status.call("Playlist tracks failed: #{friendly_error_message.call(e)}")
        ensure
          finish_loading!
          on_loaded&.call
        end
      end

      def start_tracks_async(playlist, on_loaded, loading_message:)
        @loading = true
        start_loading_status!(loading_message)
        Thread.new do
          page = source.playlist_tracks_page(playlist, limit: page_size, offset: 0)
          apply_page(playlist, page)
        rescue Services::SpotifyClient::AuthenticationError
          update_status.call('Connect Spotify first')
        rescue StandardError => e
          update_status.call("Playlist tracks failed: #{friendly_error_message.call(e)}")
        ensure
          finish_loading!
          on_loaded&.call
        end
      end

      def start_loading_status!(label)
        @loading_label = label
        @loading_started_at = Time.now
        @loading_elapsed = nil
      end

      def finish_loading!
        @loading = false
        @loading_label = nil
        @loading_started_at = nil
        @loading_elapsed = nil
        state.tracks_loading_more = false
      end

      def apply_page(playlist, page)
        tracks = page.fetch(:tracks)
        state.search_results = tracks
        state.selected_index = tracks.empty? ? nil : 0
        @offset = tracks.length
        @has_more = page.fetch(:has_more)
        update_status.call(
          tracks.empty? ? "Playlist is empty: #{playlist.name}" : "Loaded #{tracks.length} tracks from #{playlist.name}"
        )
      end

      def append_page(playlist, page)
        tracks = page.fetch(:tracks)
        state.search_results = [*state.search_results, *tracks]
        state.tracks_title = "Playlist: #{playlist.name}"
        state.selected_index ||= 0 if state.search_results.any?
        @offset += tracks.length
        @has_more = page.fetch(:has_more)
        state.tracks_loading_more = false unless @loading
        update_status.call(
          if @has_more
            "Loaded #{state.search_results.length} tracks from #{playlist.name}"
          else
            "Loaded all #{state.search_results.length} tracks from #{playlist.name}"
          end
        )
      end

      def apply_cached_tracks(playlist, tracks)
        state.search_results = tracks
        state.selected_index = tracks.empty? ? nil : 0
        state.tracks_title = "Playlist: #{playlist.name}"
        @offset = tracks.length
        @has_more = tracks.length < playlist.tracks_total
        update_status.call(cached_tracks_status(playlist, tracks))
      end

      def cached_tracks_status(playlist, tracks)
        if tracks.empty?
          "Playlist is empty: #{playlist.name}"
        elsif @has_more
          "Loaded #{tracks.length} cached tracks from #{playlist.name}"
        else
          "Loaded all #{tracks.length} tracks from #{playlist.name}"
        end
      end
    end
  end
end
