# Streamiau!

Stream tools for streamers, built to integrate with [StreamElements](https://streamelements.com/) via simple HTTP/WebSocket endpoints.

Streamiau is a [Crystal](https://crystal-lang.org/) web application powered by [Kemal](https://kemalcr.com/). It provides authenticated dashboards and public API commands for counters, phrases, Steam playtime, and YouTube latest video/short.

## Features

- **Counters** — create and manage counters, update them from the dashboard or API, and consume live updates over WebSocket (`/api/v1/counter/:username/:uuid/ws`).
- **Phrases** — manage phrase categories and fetch random/command-driven phrases through the API.
- **Steam integration** — query playtime for a Steam app. Requires a Steam Web API key.
- **YouTube integration** — fetch the latest channel video or short. Uses `yt-dlp` in the production container.
- **Authentication & sessions** — login/session-based access to dashboards, with CSRF protection for state-changing routes.
- **User/admin management** — role-based access, per-user API tokens, and admin routes for user administration.
- **MongoDB storage** — persistent data via [Moongoon](https://github.com/elbywan/moongoon).

## Requirements

- [Crystal](https://crystal-lang.org/install/) and [Shards](https://crystal-lang.org/reference/the_shards_command/)
- A running MongoDB instance
- For containerized runs: [Podman](https://podman.io/) or Docker

## Installation

```bash
git clone https://github.com/joseafga/streamiau.git
cd streamiau
cp .env.example .env
```

Configure your `.env`.

```bash
make release
make run
```

This will run the main application. If you also want the frontend, you will need to install `joseafga/streamiau-astro` in a directory alongside streamiau.

## Container

Build and run a container image (using Podman):

```bash
make container
```

The container listens on port `3000` and expects environment variables from `.env` (`--env-file .env`).

The production image includes runtime dependencies such as `yt-dlp`, which is used by YouTube-related features.

## API overview

- `WS /api/v1/counter/:username/:uuid/ws` — live counter updates
- `GET /api/v1/counter/:username/:uuid` — counter command/query
- `GET /api/v1/phrases/:username/:category` — phrase command/query
- `GET /api/v1/youtube/:username/videos/last` — latest channel video
- `GET /api/v1/youtube/:username/shorts/last` — latest channel short
- `GET /api/v1/steam/:username/:appid/hours` — Steam playtime

See [`src/streamiau/routes.cr`](src/streamiau/routes.cr) for the current route definitions and behavior.

## Contributing

1. Fork it (<https://github.com/joseafga/streamiau/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [José Almeida](https://github.com/joseafga) - creator and maintainer
