# Oto

An iOS app for [TeslaMate](https://github.com/teslamate-org/teslamate): live state, charging and
drive history, served by a small read-only HTTP API.

```
iPhone ──HTTPS + Bearer token──> Oto API ──┬─ MQTT (live)
                                           └─ PostgreSQL (history, read-only)
```

This repository contains the iOS app (`ios/`) and the API (`server/`). TeslaMate itself is not
included — Oto reads your existing TeslaMate database and MQTT broker and never modifies them.

## Requirements

- A running TeslaMate stack (PostgreSQL + Mosquitto)
- Docker and Docker Compose
- Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build the iOS app

## 1. Run the API

Create a read-only database role once, from your TeslaMate directory:

```bash
DB_PASS="$(openssl rand -base64 24 | tr -d '\n')"

docker compose exec -T database \
  psql -U teslamate -d teslamate -v ON_ERROR_STOP=1 -v pw="$DB_PASS" <<'SQL'
SELECT format('CREATE ROLE teslamate_ro LOGIN PASSWORD %L', :'pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'teslamate_ro')\gexec
SELECT format('ALTER ROLE teslamate_ro PASSWORD %L', :'pw')\gexec
GRANT CONNECT ON DATABASE teslamate TO teslamate_ro;
GRANT USAGE ON SCHEMA public TO teslamate_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO teslamate_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO teslamate_ro;
SQL
```

Then start the API:

```bash
cp .env.example .env
# DATABASE_PASS: the password above
# API_TOKEN: openssl rand -base64 32
docker compose up -d --build
curl -s localhost:8080/healthz
```

The API publishes on `127.0.0.1:8080` only and joins TeslaMate's compose network. If yours is not
`startfile_default`, change `name:` under `networks` in `compose.yml` (`docker network ls` shows it).

## 2. Run the iOS app

```bash
cd ios
xcodegen generate
open TeslaMateViewer.xcodeproj
```

Run it on a simulator or device, open **Settings**, and enter the API base URL
(`http://127.0.0.1:8080` for the simulator) and the `API_TOKEN`.

Build and test from the command line:

```bash
cd ios
xcodebuild -project TeslaMateViewer.xcodeproj -scheme TeslaMateViewer \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Using it from a phone

Keep the API bound to loopback and put it behind an HTTPS reverse proxy on the same host when the
phone is not on the same network. The app only needs a reachable base URL and the bearer token.

Keep the token private: anyone who has it can read your vehicle's location history.

## Docs

- [API reference](docs/API.md) — endpoints, parameters, response shapes
- [Tech stack](docs/TECH-STACK.md) — how the API reads TeslaMate
- [UI design](docs/UI-DESIGN.md) and [components](docs/UI-COMPONENTS.md)
- `docs/mockups/index.html` — static mockups
