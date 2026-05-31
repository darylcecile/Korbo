# Korbo

**An [opencode](https://github.com/anomalyco/opencode) client for iPad, built in SwiftUI.**

Korbo is "[openchamber](https://github.com/openchamber/openchamber) for iPad" — a
native, touch‑first client for the open‑source AI coding agent opencode. It talks
to a remote/LAN `opencode serve` instance over REST + SSE + WebSocket and presents
the familiar three‑pane workspace: **sessions · conversation · git/files/context**.

> Korbo does not run the agent. opencode runs as a server somewhere you control;
> Korbo is the iPad front‑end.

## Status

Early scaffold (M0). The iPad app builds and renders the three‑pane shell; the
networking layer and features are being built per the docs below.

## Documentation

- [`docs/PRD.md`](docs/PRD.md) — product requirements, architecture, milestones.
- [`docs/FEATURE_CHECKLIST.md`](docs/FEATURE_CHECKLIST.md) — exhaustive opencode‑GUI
  parity checklist (P0/P1/P2).
- [`docs/OPENCODE_API.md`](docs/OPENCODE_API.md) — verified opencode server API
  (endpoints, 77 SSE event types, data models) the client targets.

## Develop

Requirements: macOS + Xcode 26+, [`xcodegen`](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate            # regenerate Korbo.xcodeproj from project.yml
open Korbo.xcodeproj          # or build from CLI:
xcodebuild -project Korbo.xcodeproj -scheme Korbo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

The `.xcodeproj` is generated and git‑ignored — edit `project.yml` and sources,
then regenerate.

### Layout
```
Korbo/
  App/        KorboApp, AppModel, KorboStore, RelativeTime
  Features/   Root, Sessions, Chat, Context (SwiftUI views)
  Networking/ OpencodeClient, OpencodeModels, OpencodeEvents
  Resources/  Assets.xcassets
docs/         PRD, FEATURE_CHECKLIST, OPENCODE_API
project.yml   XcodeGen spec (iPad‑only, iOS 17+)
```