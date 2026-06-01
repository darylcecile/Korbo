# Korbo — Product Requirements Document

**An opencode client for iPad, built in SwiftUI.**

| | |
|---|---|
| Status | Draft v0.1 |
| Platform | iPadOS 26+ (iPad‑only, landscape‑first; portrait supported) |
| Tech | SwiftUI, Swift Concurrency, URLSession (REST + SSE + WebSocket) |
| Backend | A remote/LAN [opencode](https://github.com/anomalyco/opencode) server (`opencode serve`) |
| Design north star | [openchamber](https://github.com/openchamber/openchamber) — its desktop/web opencode GUI |

---

## 1. Summary

Korbo is a native iPad app that gives opencode — the open‑source AI coding agent —
a first‑class touch/tablet client. It is, in spirit, "openchamber for iPad": the
same three‑pane workspace (sessions · conversation · git/files/context), the same
dark, low‑chroma aesthetic, the same agentic chat workflow, adapted to iPadOS
(touch, Pencil, multitasking, keyboard, share sheet, notifications).

Korbo does **not** run the agent itself. opencode runs as a server on a dev
machine / VM / container; Korbo is a thin, fast, beautiful client that talks to it
over HTTP (REST), SSE (`/event`), and WebSocket (PTY). See
[`OPENCODE_API.md`](./OPENCODE_API.md) for the verified API surface.

## 2. Goals & non‑goals

### Goals
- **G1** — Connect to one or more remote opencode servers securely and reliably.
- **G2** — Full agentic chat: send prompts, stream assistant text/reasoning/tool
  calls live, with rich rendering (markdown, diffs, code, todos, attachments).
- **G3** — Session management on par with openchamber: list/group/search, create,
  fork, share, revert, archive, rename, delete, worktree/branch sessions.
- **G4** — Git workflow: changes, stage, commit (incl. AI message), sync, branch,
  PR, history, diff viewer, conflict handling.
- **G5** — Files: tree, viewer/editor with syntax highlighting, autosave/manual‑save.
- **G6** — Context & cost visibility: token usage ring, context items, model/agent
  selection, reasoning effort.
- **G7** — Permission & question flows handled inline and via notifications.
- **G8** — A design that visibly matches openchamber's quality on iPad.

### Non‑goals (v1)
- Bundling/embedding the opencode runtime on‑device (server is remote).
- Full embedded VS Code (we offer "open in editor" deep links instead).
- Becoming a general git client beyond what opencode/openchamber expose.
- iPhone‑optimized layout (responsive later; iPad‑first now).

## 3. Personas & top user journeys

- **The mobile developer** continues an agent session from the couch/commute:
  reviews streamed output, approves a permission, commits, syncs.
- **The reviewer** opens a worktree/PR session, reads the diff, leaves the agent
  to address comments, watches tool calls live.
- **The tinkerer** connects to a home‑lab opencode VM over Tailscale/reverse proxy
  and drives multiple projects.

Key journeys: (a) connect to server → pick project → new session → prompt →
stream → approve permission → commit & sync. (b) reopen recent session → revert a
turn → re‑prompt. (c) switch model/agent mid‑session.

## 4. Architecture

```
┌────────────────────────── iPad (Korbo, SwiftUI) ───────────────────────────┐
│  RootView (3‑pane)                                                          │
│   ├─ SessionsSidebar      ├─ ChatPane (+composer)     ├─ ContextPane        │
│  AppModel / Stores (sessions, chat, git, files, settings, connection)      │
│  OpencodeClient ── REST ──┐   EventStream ── SSE /event ──┐  PTY ── WS ──┐  │
└───────────────────────────┼───────────────────────────────┼─────────────┼──┘
                            ▼                               ▼             ▼
              Reverse proxy / tunnel (TLS + auth)  ── http://host:4096 ──► opencode serve
```

- **Layered**: `Networking` (transport + Codable models) → `Stores` (observable
  state, one per domain) → `Features` (SwiftUI views). No view talks to the network
  directly.
- **Live‑first**: a single SSE connection per active server drives almost all UI
  updates. REST is used for initial loads and commands. Reducer maps 77 event
  types → store mutations.
- **Offline/resilience**: cached last‑known session list & messages; reconnect with
  backoff; clear connection‑status banner.

### Connection & security model (important)
opencode's server is **unauthenticated and localhost‑trusted**. Korbo therefore:
- Stores servers as `{name, baseURL, headers}`; credentials (bearer/basic) live in
  the **iOS Keychain**.
- Recommends and documents three deployment options: (1) reverse proxy w/ TLS+auth,
  (2) SSH/Tailscale/relay tunnel, (3) trusted LAN (`--hostname 0.0.0.0`) for dev.
- Never ships a mode that encourages exposing a raw server publicly.
- Validates server identity (cert pinning optional), supports multiple saved
  servers with quick switching.

## 5. Feature requirements

Each area lists what openchamber does and what Korbo must deliver. The exhaustive,
trackable list lives in [`FEATURE_CHECKLIST.md`](./FEATURE_CHECKLIST.md).

### 5.1 App shell & layout
- Three‑pane layout: sessions (left), conversation (center), context (right).
- Right pane is collapsible; panes resize; auto‑collapse at narrow widths (Split
  View/Slide Over). Landscape‑first; portrait collapses to center + drawers.
- Top bar: model/agent selector, session title + project/branch/diff subtitle,
  context‑usage ring (%), open‑in‑editor, right‑sidebar toggle, account.
- Bottom terminal dock (toggleable). Command palette. Keyboard shortcuts for
  hardware keyboards (mirror openchamber's set where sensible on iPad).

### 5.2 Sessions (left sidebar)
- Grouped list: recent (today/yesterday/7‑days/older), by project, by
  worktree/branch, archived. Per‑item: title, project, branch, +/− diff, time,
  streaming/pin badges.
- Actions: new session, new worktree/branch session, search, create/rename/fork/
  share/archive/delete/duplicate/pin. Multi‑select bulk actions.
- Live status (streaming, idle, error) from events.

### 5.3 Conversation (center)
- Message list: user vs assistant; model badge, agent badge, reasoning badge.
- Part rendering: **text** (markdown w/ code blocks, copy, syntax highlight),
  **reasoning** (collapsible "thinking"), **tool** calls (bash/edit/read/write/
  grep/glob/task/todo… with expandable I/O and **diff viewer** for edits),
  **file**/image attachments, **todo** lists, **step**/snapshot/patch/compaction.
- Footers: tokens, cost, duration, timestamp. Message actions: copy, share, fork,
  revert/unrevert.
- Streaming: text/reasoning/tool deltas render incrementally; abort/stop control.
- Inline **permission** cards (allow once/always/reject) and **question** cards.
- Empty, error, and pending‑changes states.

### 5.4 Composer
- Multiline auto‑growing input. `@` mentions (files/agents), `/` commands/skills,
  `!` shell. Attachments (files + images; paste & drag‑drop; document/photo
  pickers; Pencil/scribble). Model selector, reasoning‑effort selector, agent
  selector (Build/Plan/…). Send (⌘↵) / Stop. Draft persistence per session.

### 5.5 Git (right tab)
- Branch selector; changes list (M/A/D/?) with +/− and stage toggles; revert
  per‑file/all; commit message box + **AI generate**; commit; commit & sync;
  fetch/pull/push/sync; history/log + graph; PR create/view/merge; conflict
  dialog; stashes; git identities.

### 5.6 Files (right tab)
- File tree (search, context menu: open/new/rename/delete). Viewer/editor with
  syntax highlighting, line numbers, find. **Autosave vs manual‑save** toggle with
  dirty indicator and ⌘S. Multiple open files (tabs).

### 5.7 Context (right tab)
- Context items (files/attachments/agents/skills) with token counts; per‑category
  token‑usage breakdown + limit warning; modes (diff/file/context/plan/preview).

### 5.8 Settings
- **Connection/Remote instances** (servers, auth, verify, switch) — P0.
- **Providers & API keys** (incl. OAuth flows), **Models** (favorites/cycling).
- **Agents** (list/create/edit), **Commands**, **Skills**, **MCP servers**
  (incl. OAuth), **Plugins**.
- **Appearance** (theme light/dark/system, syntax themes, custom themes, fonts,
  density, radius), **Chat**, **Notifications** (templates, sound), **Sessions**
  (retention), **Keyboard shortcuts**, **Git identities**, **Behavior**,
  **Usage/quota**, **Voice** (later), **i18n** (later).

### 5.9 Terminal
- PTY session(s) over WebSocket; shell I/O; copy/paste; theme‑matched. P1.

### 5.10 iPad‑native extras
- Notifications (permission/question/idle/error) via local notifications.
- Multitasking (Split View / Stage Manager), keyboard shortcuts, share sheet,
  Handoff (later), Shortcuts/App Intents (later), Pencil scribble in composer.

## 6. Non‑functional requirements
- **Performance**: 60fps scrolling with long sessions (virtualized lists);
  streaming deltas batched to avoid layout thrash; large diffs lazy‑rendered.
- **Reliability**: SSE auto‑reconnect; idempotent client‑supplied message IDs;
  graceful handling of all 77 event types (unknown types ignored, not fatal).
- **Security**: Keychain for secrets; no plaintext tokens; TLS by default for
  remote; optional cert pinning.
- **Accessibility**: Dynamic Type, VoiceOver labels, sufficient contrast, ≥44pt
  touch targets.
- **Testability**: protocol‑abstracted client for mockable stores; snapshot tests
  for part rendering; decode tests against captured event fixtures.

## 7. Compatibility & risks
- opencode API is fast‑moving and partly under `experimental/*`; pin to a known
  server version, degrade gracefully when endpoints/events are missing.
- No server auth means the proxy/tunnel layer is **required** for safe remote use;
  Korbo must make the secure path the easy path.
- PTY/WebSocket and large‑file editing are the heaviest items — schedule as P1.

## 8. Milestones (no dates; sequence only)
- **M0 — Skeleton (done in this PR)**: iPad app builds, three‑pane shell, theme,
  typed client/model stubs, docs (PRD, checklist, API).
- **M1 — Connect & read**: server config + Keychain, health, SSE plumbing, list
  sessions/messages, render a static conversation from the API.
- **M2 — Live chat**: prompt send, streaming text/reasoning/tool, abort, model/
  agent/effort selection, markdown + diff rendering, permission/question cards.
- **M3 — Git**: changes/stage/commit/AI‑message/sync/branch/history/diff.
- **M4 — Sessions++**: grouping/search/fork/share/revert/archive/worktree.
- **M5 — Files & context**: tree, viewer/editor, autosave toggle, context/token UI.
- **M6 — Settings**: providers/agents/commands/skills/MCP/appearance/notifications.
- **M7 — Terminal + iPad polish**: PTY, multitasking, shortcuts, notifications, a11y.

## 9. Open questions (to confirm with stakeholder)
1. **Server access** — what's the remote you'll set up (reverse proxy URL + bearer
   token? Tailscale? plain LAN)? This shapes the M1 connection UI.
2. **v1 scope** — is the target full openchamber parity, or a focused "chat + git +
   sessions" v1 with files/terminal/settings following?
3. **Auth to providers** — managed via opencode server config, or also editable
   from Korbo (provider API keys / OAuth in‑app)?
4. **Min iPadOS** — 17 (broad) vs 18+ (newer SwiftUI APIs)?
5. **Branding** — keep "Korbo" name/accent, or match openchamber's palette exactly?
