# Oto

An iOS app for [TeslaMate](https://github.com/teslamate-org/teslamate): live state, charging and
drive history, served by a small read-only HTTP API.

```
iPhone ──HTTPS + Bearer token──> Oto API ──┬─ MQTT (live)
                                           └─ PostgreSQL (history, read-only)
```

This repository contains the iOS app (`ios/`) and the API (`server/`), plus a deploy bundle
(`deploy/`) that brings up TeslaMate, Grafana and the API together. Oto only reads TeslaMate's
data; it never modifies it.

## Deploy on a server

### What the server needs

- Docker Engine with the Compose v2 plugin, on amd64 or arm64
- 2 GB RAM and about 5 GB free disk (the images alone are ~2 GB)
- Outbound internet for image pulls and the Tesla API
- No inbound ports: every service binds to `127.0.0.1`, and only a reverse proxy you add yourself
  would listen publicly

### Deploy

```bash
git clone https://github.com/Huskkyq/oto.git
cd oto && bash deploy/deploy.sh
```

That is the whole deployment. The script generates every secret into `deploy/.env` (mode 600),
starts TeslaMate, Grafana and the API, creates the read-only database role, and prints the API
token. Re-running it is safe: existing secrets are kept and only changed services restart.

Then onboard the car over an SSH tunnel:

```bash
ssh -N -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 -L 8080:127.0.0.1:8080 user@your-server
```

Open <http://127.0.0.1:4000> and sign in with your Tesla tokens. Grafana is at
<http://127.0.0.1:3000> (first login `admin` / `admin` — change it).

### Configuration

Everything lives in `deploy/.env`, written the first time the script runs:

| Variable | Default | Purpose |
| --- | --- | --- |
| `ENCRYPTION_KEY` | generated | Encrypts the Tesla tokens TeslaMate stores. **Changing it loses them.** |
| `DATABASE_PASS` | generated | Postgres superuser password |
| `RO_PASSWORD` | generated | The `teslamate_ro` role the API reads with |
| `API_TOKEN` | generated | Bearer token the app sends; `grep API_TOKEN deploy/.env` prints it |
| `TESLAMATE_PORT` | `4000` | TeslaMate web UI, loopback only |
| `GRAFANA_PORT` | `3000` | Grafana, loopback only |
| `API_PORT` | `8080` | Oto API, loopback only |

`API_TOKEN` must be at least 24 characters (the generated one is 64). If a port is already taken,
edit `deploy/.env` and run the script again.

### Reach the API from the phone

The API is loopback-only, so the phone needs a route in:

- **Reverse proxy** — Caddy, nginx or Traefik on the same host, terminating TLS and proxying to
  `127.0.0.1:8080`. With Caddy that is a three-line site:

  ```
  api.example.com {
      reverse_proxy 127.0.0.1:8080
  }
  ```

  Then use `https://api.example.com` as the base URL in the app.
- **Tailscale or WireGuard** — join the phone to the same network and expose the loopback port from
  the host (Tailscale Serve, or a local WireGuard listener).

Never publish the port directly: the bearer token would travel in clear text.

### Update

```bash
cd oto && git pull
docker compose -f deploy/compose.yml --env-file deploy/.env pull teslamate grafana database mosquitto
bash deploy/deploy.sh
```

## Run locally

To run only the API against a TeslaMate stack you already have:

```bash
cp .env.example .env     # DATABASE_PASS and API_TOKEN; see the comments in the file
docker compose up -d --build
curl -s localhost:8080/healthz
```

Create the read-only role once (the deploy script does this for you):

```bash
docker compose exec -T database \
  psql -U teslamate -d teslamate -v ON_ERROR_STOP=1 -v pw="<role password>" <<'SQL'
SELECT format('CREATE ROLE teslamate_ro LOGIN PASSWORD %L', :'pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'teslamate_ro')\gexec
GRANT CONNECT ON DATABASE teslamate TO teslamate_ro;
GRANT USAGE ON SCHEMA public TO teslamate_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO teslamate_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO teslamate_ro;
SQL
```

`compose.yml` joins TeslaMate's compose network as an external one. If yours is not
`startfile_default`, change `name:` under `networks` (`docker network ls` shows it).

## Run the iOS app

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ios
xcodegen generate
open TeslaMateViewer.xcodeproj
```

Run it on a simulator or device, open **Settings**, and enter the API base URL
(`http://127.0.0.1:8080` for the simulator) and the API token.

Build from the command line:

```bash
cd ios
xcodebuild -project TeslaMateViewer.xcodeproj -scheme TeslaMateViewer \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Keep the token private: anyone who has it can read your vehicle's location history.

## Docs

- [API reference](docs/API.md) — endpoints, parameters, response shapes
- [Tech stack](docs/TECH-STACK.md) — how the API reads TeslaMate
- [UI design](docs/UI-DESIGN.md) and [components](docs/UI-COMPONENTS.md)
- `docs/mockups/index.html` — static mockups
