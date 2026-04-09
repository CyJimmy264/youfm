# YouFM

Desktop music player on Ruby + Qt with a Spotify-first architecture.

The app follows the same broad pattern as `qtimetrap`:

- `Zeitwerk` autoloading
- small DI container
- `app/models`, `app/services`, `app/view_models`, `app/views`
- Qt window wired through a single `MainWindow`

## Current Scope

- Spotify as the primary music source
- Search tracks through Spotify Web API
- Show current playback state
- Play / pause on an active Spotify Connect device
- Source abstraction so other providers can be added later

## Requirements

- Ruby `>= 3.2`
- Qt bridge gem: `qt >= 0.1.7`
- A Spotify user access token with playback scopes

## Spotify Auth

For now, the app expects a ready access token in the environment:

```bash
export SPOTIFY_ACCESS_TOKEN=...
```

Recommended scopes:

- `user-read-playback-state`
- `user-modify-playback-state`
- `user-read-currently-playing`

Optional:

```bash
export SPOTIFY_API_BASE_URL=https://api.spotify.com/v1
export YOUFM_ENV=development
export YOUFM_THEME=dark
```

## Run

```bash
bundle install
bundle exec bin/youfm
```

## Structure

- `app/services/spotify_client.rb`: Web API adapter
- `app/services/music_sources/spotify_source.rb`: source abstraction
- `app/view_models/main_view_model.rb`: UI state + actions
- `app/views/main_window.rb`: Qt window
- `config/application.rb`: boot, loader, Qt app
