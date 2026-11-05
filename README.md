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

## Deploy to a server

On any Docker host:

```bash
git clone https://github.com/Huskkyq/oto.git
cd oto && bash deploy/deploy.sh
```

That is the whole deployment. It generates every secret into `deploy/.env`, starts TeslaMate,
Grafana and the API, creates the read-only database role, and prints the API token. Re-running it
is safe: existing secrets are kept and only changed services restart.

Afterwards, open TeslaMate (loopback only — use the SSH tunnel the script prints) and sign in with
your Tesla tokens. Then point the iOS app at the API.

The API binds to `127.0.0.1`. Give the phone a reachable HTTPS URL by putting a reverse proxy in
front of it, or by exposing the port over Tailscale or WireGuard.

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
