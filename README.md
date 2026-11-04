# TeslaMate iOS Viewer

A native iOS app for TeslaMate's live and historical vehicle data.

```
iPhone (SwiftUI) ──HTTPS + Bearer token──> Caddy on <server-ip> (<domain>)
                                              │ 127.0.0.1:9080
                                              ▼
                                             teslamate-ios-api (container)
                                              ├─ MQTT (teslamate-mosquitto)
                                              └─ PostgreSQL (read-only role)
```

The API runs in a container next to the TeslaMate stack on the server, on the same compose
network. Postgres and Mosquitto are not published on the host, and TeslaMate itself is not
modified. The same compose file still runs locally against a Mac TeslaMate stack for
development.

---

## 1. Create the read-only database role

```bash
cd /Users/sevan/ai-tasks/teslamate
DB_PASS="$(openssl rand -base64 24 | tr -d '\n')"

docker compose -f STARTFILE/docker-compose.yml exec -T database \
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

`private.tokens` stays inaccessible; the API never needs it.

## 2. Configure the API

```bash
cd odo
cp .env.example .env
# Set DATABASE_PASS to the password above and API_TOKEN to:
openssl rand -base64 32
```

Confirm the compose network name:

```bash
docker network ls | grep startfile
```

It is normally `startfile_default`, as in `compose.yml`.

## 3. Run

```bash
cd odo
docker compose up -d --build
docker compose logs -f api
```

Smoke test on the Mac:

```bash
TOKEN="$(grep '^API_TOKEN=' .env | cut -d= -f2-)"
curl -s localhost:8080/healthz
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/v1/cars
```

The port is bound to `127.0.0.1` only.

## 4. Public access through a reverse proxy

The server that runs TeslaMate also runs the API, so the phone never needs a tunnel to the
Mac. Caddy on `<server-ip>` terminates TLS for `https://<domain>` (Let's Encrypt,
TLS-ALPN-01 — `:80` belongs to Grafana) and reverse-proxies to `127.0.0.1:9080`, which the
API container publishes on loopback only. The Authorization header is forwarded untouched.

Deployment on the server, under `/opt/teslamate-ios-api`:

```bash
ssh root@<server-ip>
cd /opt/teslamate-ios-api
docker compose up -d --build
```

The compose file there pins `mem_limit: 192m`, joins the external `teslamate_default`
network, and reads its `.env` (same variables as above, with `DATABASE_HOST=database` and
`MQTT_HOST=mosquitto`). The server's database needs the same read-only role as section 1,
created once against the `teslamate` database.

`/etc/caddy/odo.caddy` holds the site block; `systemctl reload caddy` picks up changes.
```
<domain> {
	encode zstd gzip
	tls {
		issuer acme {
			disable_http_challenge
		}
	}
	reverse_proxy 127.0.0.1:9080
}
```

No `PROXY_TOKEN` is configured yet, so every client behind the proxy shares one rate-limit
bucket. Before wider use, configure rate limiting, logs that exclude tokens and
sensitive location data; verify that authentication reaches the API and that the server's
PostgreSQL and MQTT are not publicly exposed. The public `/healthz` endpoint
remains unauthenticated. Data routes are limited before authentication, including invalid
tokens; `/live` also has a separate lower limit. By default, limits use the socket address,
so clients behind the proxy share a limit. For per-client limits, set a separate, strong
`PROXY_TOKEN` on the API and configure the proxy to overwrite `X-Odo-Proxy-Token` with that
value and `X-Odo-Client-IP` with the actual connecting client's single IP address. Strip
these headers from all incoming requests before setting them; never forward client-supplied
values. Keep the proxy token private and distinct from the API token. Requests without a
valid proxy token fall back to the socket address; arbitrary forwarded headers are ignored.
Configure edge rate limiting too, including for public `/healthz`. The proxy cannot serve
fresh API data if the server or its containers are unavailable.

## 5. Build the iOS app

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd odo/ios
xcodegen generate
open TeslaMateViewer.xcodeproj
```

Or from the command line:

```bash
cd odo/ios
xcodebuild -project TeslaMateViewer.xcodeproj -scheme TeslaMateViewer \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the unit tests:

```bash
xcodebuild -project TeslaMateViewer.xcodeproj -scheme TeslaMateViewer \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Security notes

- The app stores the Bearer token in the Keychain, never in `UserDefaults` or source.
- The API returns no VIN, database password or MQTT credentials.
- Requests are rate limited; the token is compared in constant time.
- Postgres and MQTT stay on the private compose network.
- GPS history is sensitive: protect the public HTTPS endpoint and exclude tokens and location data from proxy logs.

## Data freshness

Live values are MQTT retained messages. The API reports `received_at`, `oldest_received_at`, and
`stale`. A sleeping car has old values by design — use `values.state` to distinguish that from a
disconnected API.

## Layout

```
odo/
  compose.yml
  server/          Node 22 API (pg + mqtt)
  ios/             SwiftUI app (XcodeGen project)
  docs/API.md
  docs/API.zh-CN.md
  docs/TECH-STACK.md
  docs/TECH-STACK.zh-CN.md
  docs/UI-DESIGN.md
  docs/UI-COMPONENTS.md
  docs/mockups/    static HTML mockups (open index.html, components.html)
```
