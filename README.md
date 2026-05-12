# YouFM

Desktop music player on Ruby + Qt with a Spotify-first architecture.

The app follows the same broad pattern as `qtimetrap`:

- `Zeitwerk` autoloading
- small DI container
- `app/models`, `app/services`, `app/view_models`, `app/views`
- Qt window wired through a single `MainWindow`

## Current Scope

- Spotify as the primary music source
- PKCE OAuth login inside the app
- Search tracks through Spotify Web API
- Show current playback state
- Switch active Spotify Connect device
- Show queue and user playlists
- Play / pause and start playback from selected track or playlist
- Source abstraction so other providers can be added later

## Requirements

- Ruby `>= 3.2`
- Qt bridge gem: `qt >= 0.1.7`
- A Spotify user access token with playback scopes

## Spotify Auth

The app now supports Spotify Authorization Code with PKCE inside the UI.
You only need to provide Spotify app metadata:

Create a `.env` file in the project root:

```dotenv
SPOTIFY_CLIENT_ID=...
SPOTIFY_REDIRECT_URI=http://127.0.0.1:8989/callback
```

The redirect URI must also be registered in your Spotify app settings.

Default scopes:

- `user-read-playback-state`
- `user-modify-playback-state`
- `user-read-currently-playing`
- `playlist-read-private`
- `playlist-read-collaborative`

You can still provide `SPOTIFY_ACCESS_TOKEN` manually, but the intended flow is OAuth from inside the app.

Optional:

```dotenv
SPOTIFY_API_BASE_URL=https://api.spotify.com/v1
SPOTIFY_ACCOUNTS_BASE_URL=https://accounts.spotify.com
LASTFM_API_KEY=...
LASTFM_SECRET=...
YOUFM_ENV=development
YOUFM_THEME=dark
```

`dotenv` loads `.env`, `.env.local`, `.env.development`, and `.env.development.local` automatically at boot.

## Run

```bash
bundle install
bundle exec bin/youfm
```

## Structure

- `app/services/spotify_client.rb`: Web API adapter
- `app/services/spotify_authenticator.rb`: PKCE OAuth flow + local callback capture
- `app/services/spotify_token_store.rb`: persisted access/refresh tokens
- `app/services/music_sources/spotify_source.rb`: source abstraction
- `app/view_models/main_view_model.rb`: UI state + actions
- `app/views/main_window.rb`: Qt window
- `config/application.rb`: boot, loader, Qt app
