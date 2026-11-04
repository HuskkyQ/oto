# Odo — Technology Stack

This inventory separates code already present from planned work. Versions describe repository configuration, not a verified deployment. See [STATUS.md](STATUS.md) for feature progress.

## Architecture

```text
iPhone (SwiftUI)
  │ HTTPS + bearer token
  ▼
Public server (fixed domain, HTTPS reverse proxy)
  │ Private connection over Tailscale
  ▼
Node.js read-only API on the Mac (Docker)
  ├── PostgreSQL: TeslaMate historical data, SELECT-only role
  └── MQTT / Mosquitto: TeslaMate live values
```

The API is configured to listen on the Mac's loopback interface and join TeslaMate's existing Docker network. The intended deployment uses a public reverse proxy connected to the Mac through Tailscale; the iPhone does not need Tailscale. The proxy terminates public TLS and forwards the bearer token to the API over the private connection. The proxy and end-to-end deployment have not yet been configured or verified. If the Mac, API, or private connection is unavailable, the proxy cannot serve fresh API data.

## iOS application

| Technology | Purpose | Status |
|---|---|---|
| Swift 5.9, SwiftUI, iOS 17+ | Native iPhone UI and application logic | Configured; builds for the iOS Simulator. Live screen and the shared shell exist; four tab screens are placeholders. |
| Xcode 15+, XcodeGen | Build tools and project generation from `ios/project.yml` | Configured/documented; no generated Xcode project is checked in. |
| URLSession, async/await, Codable | HTTP requests and JSON models | Source present. |
| Security / Keychain | Store the API bearer token | Source present. |
| Swift Charts | Historical line and bar charts | Chart component exists; remaining screens are incomplete. |
| MapKit | Vehicle positions and route maps | Planned; map screens are incomplete. The WGS-84 to GCJ-02 transformation exists but is not wired in. |
| SwiftData | Cache last successful responses for offline viewing | Planned; not implemented. |
| XCTest | iOS unit testing | Test target configured; test directory is empty. |

No third-party iOS packages are declared in `ios/project.yml`. The 3D vehicle concept is deferred; its proposed RealityKit and USDZ stack is not required for the current app.

## API and data

| Technology | Purpose | Status |
|---|---|---|
| Node.js 22, JavaScript ES modules, `node:http` | Standalone JSON API without a web framework | Source present; `server/package.json` requires Node ≥22 and the Docker image uses Node 22 Alpine. |
| `pg` ^8.23.1 | Query TeslaMate PostgreSQL data | Direct dependency; lockfile resolves 8.23.1. |
| `mqtt` ^5.16.1 | Subscribe to live TeslaMate MQTT topics | Direct dependency; lockfile resolves 5.16.1. |
| PostgreSQL | Historical trips, charges, positions and statistics | Existing TeslaMate service; Odo's intended role has SELECT access only. Version is supplied by the TeslaMate deployment. |
| MQTT / Mosquitto | Vehicle state feed and in-memory live cache | Existing TeslaMate service; version depends on deployment. |
| Node built-in test runner (`node --test`) | API unit tests | Configured in `server/package.json`; see STATUS for recorded results. |

API authentication uses a bearer token; `/healthz` is public and the data endpoints require authentication. See [API.md](API.md) for the contract.

## Deployment and design

| Technology | Purpose | Status |
|---|---|---|
| Docker and Docker Compose | Containerize the API and attach it to TeslaMate's network | Configuration present in `compose.yml` and `server/Dockerfile`. |
| Public HTTPS reverse proxy | Fixed-domain entry point and request forwarding | Planned; proxy software, hosting and configuration are not yet selected or deployed. |
| Tailscale HTTPS | Private connection from the proxy server to the Mac | Planned; not verified. The iPhone does not need Tailscale. |
| HTML, CSS, inline SVG and JavaScript | Standalone screen and component mockups | Present in [mockups/index.html](mockups/index.html) and [mockups/components.html](mockups/components.html); these are design references, not the iOS runtime. |

## Decisions still open

- Manually entered third-party charging costs are deferred. Local storage would create a second source of truth; writing to TeslaMate would violate the current read-only architecture. No persistence technology has been chosen. See [PRD §10](PRD.md).
- The existing app is incomplete: the missing root views block the iOS build. Device validation, offline cache and map integration remain unfinished.

## References

- [API contract](API.md) · [Product requirements](PRD.md) · [UI design](UI-DESIGN.md) · [Component inventory](UI-COMPONENTS.md) · [Project status](STATUS.md)
- [Server dependencies](../server/package.json) · [iOS project configuration](../ios/project.yml) · [Deployment configuration](../compose.yml)
- 中文版：[TECH-STACK.zh-CN.md](TECH-STACK.zh-CN.md)
