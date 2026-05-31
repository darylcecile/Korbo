# Korbo — Feature Checklist (opencode GUI parity)

Exhaustive catalogue of everything the opencode GUI (openchamber) does, as the
coverage target for the Korbo iPad app. Priorities: **P0** core / **P1** important
/ **P2** later. Checkboxes track implementation (all unchecked at M0).

Legend: `[ ]` not started · `[~]` partial · `[x]` done.

---

## 1. App shell & global layout
- [ ] P0 Three‑pane layout: sessions · conversation · context
- [ ] P0 Collapsible right sidebar (toggle)
- [ ] P1 Resizable panes (drag dividers) with min/max widths
- [ ] P1 Auto‑collapse right/left at narrow widths (Split View / Stage Manager)
- [ ] P0 Landscape‑first layout; portrait collapses to center + drawers
- [ ] P0 Top bar: model/agent selector, session title, project·branch·diff subtitle
- [ ] P0 Top bar: context‑usage ring (%)
- [ ] P1 Top bar: "open in editor" deep link (vscode://, etc.)
- [ ] P1 Top bar: local/remote (server) selector
- [ ] P0 Top bar: account/avatar menu
- [ ] P1 Bottom terminal dock (toggle, resize)
- [ ] P1 Command palette (⌘P): sessions, files, commands, settings, actions
- [ ] P1 Hardware‑keyboard shortcuts (mirror openchamber set where sensible)
- [ ] P2 Mini chat window / multi‑window (Stage Manager)
- [ ] P0 Dark theme baseline; light/system later

## 2. Sessions sidebar (left)
- [x] P0 Session list with live data from `/session` + events
- [x] P0 Grouping: recent (today/yesterday/7‑days/older)
- [ ] P1 Grouping: by project/folder
- [ ] P1 Grouping: by worktree/branch
- [x] P0 Grouping: archived section
- [x] P0 Item: title, project, +/− diff, relative time *(branch is workspace‑level in opencode, not per‑session — omitted)*
- [~] P1 Item: streaming/active badge *(active dot done; pin/favourite deferred)*
- [x] P0 New session
- [ ] P1 New worktree/branch session
- [x] P0 Search/filter sessions
- [ ] P2 Calendar/activity (by date)
- [x] P0 Context menu: rename
- [x] P0 Context menu: delete (confirm)
- [x] P0 Context menu: archive/unarchive
- [ ] P1 Context menu: fork/duplicate
- [ ] P1 Context menu: share (link) / unshare *(API: `/session/{id}/share` exists — deferrable)*
- [ ] P1 Context menu: pin/unpin
- [ ] P2 Multi‑select + bulk actions (archive/delete/pin)
- [ ] P2 Drag‑reorder / sort options

## 3. Conversation view (center)
- [ ] P0 Message list, user vs assistant distinction
- [ ] P0 Message header: sender/model logo, model badge, agent badge
- [ ] P1 Reasoning‑effort/variant badge
- [ ] P0 **Text part**: markdown rendering
- [ ] P0 Code blocks: syntax highlighting + copy button
- [ ] P0 Markdown: lists, tables, blockquotes, links, emphasis, inline code
- [ ] P0 **Reasoning part**: collapsible "thinking" block (streamed)
- [ ] P0 **Tool part**: generic tool call card (name, status, expand)
- [ ] P0 Tool: bash/shell command + output (collapsible)
- [ ] P0 Tool: edit/write/patch with **diff viewer** (added/removed)
- [ ] P1 Tool: read/grep/glob/list rendering
- [ ] P1 Tool: task (subagent) nested rendering
- [ ] P1 Tool: full‑output modal/expand
- [ ] P0 **Todo** list rendering (todowrite/`todo.updated`)
- [ ] P0 **File/image attachments** inline (user + assistant)
- [ ] P1 Step / snapshot / patch / compaction parts
- [ ] P0 Per‑message footer: tokens, cost, duration, timestamp
- [ ] P0 Message actions: copy
- [ ] P1 Message actions: share, fork, revert/unrevert
- [ ] P0 Streaming: incremental text/reasoning/tool deltas
- [ ] P0 Abort/stop active run
- [ ] P0 Inline **permission** card (allow once / always / reject)
- [ ] P1 Inline **question** card (reply / reject)
- [ ] P0 Empty state
- [ ] P0 Error state (+ retry)
- [ ] P1 Pending‑changes bar (unstaged git)
- [ ] P1 Auto‑scroll w/ "scroll to bottom" affordance
- [ ] P2 Inline code comments / drafts

## 4. Composer
- [ ] P0 Multiline auto‑growing input
- [ ] P0 Placeholder "@ for files/agents; / for commands; ! for shell"
- [ ] P0 Send (⌘↵) and Stop states
- [ ] P0 `@` mention autocomplete: files
- [ ] P1 `@` mention autocomplete: agents
- [ ] P1 `/` command/skill autocomplete
- [ ] P1 `!` shell prefix routing
- [ ] P0 Attach file (document picker)
- [ ] P0 Attach image (photo picker) + preview
- [ ] P1 Paste image; drag‑drop files
- [ ] P1 Attachment chips (remove, size/path)
- [ ] P0 Model selector
- [ ] P1 Reasoning‑effort selector
- [ ] P0 Agent/mode selector (Build/Plan/…)
- [ ] P1 Draft persistence per session
- [ ] P2 Draft preset chips / starters
- [ ] P2 Expand/focus‑mode input
- [ ] P2 Pencil scribble input

## 5. Git tab (right)
> opencode's server exposes a **read + diff** VCS surface only (`/vcs`,
> `/vcs/diff`, `/vcs/apply`). Mutations (commit / push / pull / branch
> switch / stage) are **not** in its REST API — they need a server-side git
> bridge (or the agent-shell endpoint, which pollutes the chat) and are
> deferred. M3 delivers the diff-review surface below.
- [x] P0 Branch + base header (current branch → default branch) — *display; switch deferred*
- [ ] P1 Create new branch — *no API*
- [x] P0 Changes list: path, status (M/A/D/?), +/−
- [x] P0 Working‑vs‑branch diff toggle (`mode=git` / `mode=branch`)
- [ ] P0 Stage/unstage per file; select‑all — *no git-index API*
- [ ] P0 Revert per file; revert all — *possible via reverse `/vcs/apply`; deferred*
- [x] P0 Inline diff viewer per file (hunks, add/remove/context coloring)
- [x] P0 Live refresh on `session.diff` / `file.edited` / `vcs.branch.updated`
- [ ] P0 Commit message box — *no commit API*
- [ ] P0 **Generate** AI commit message — *no commit API*
- [ ] P0 Commit — *no commit API*
- [ ] P0 Commit & sync (push) — *no push API*
- [ ] P1 Fetch / pull / push / sync actions — *no API*
- [ ] P1 History/log list (hash, author, time, message) — *no log API*
- [ ] P2 Git graph visualization
- [ ] P1 Pull request: create (title/desc/base)
- [ ] P1 Pull request: view status/reviews/CI
- [ ] P2 Pull request: merge / request review / comment
- [ ] P2 Branch integration (merge/rebase/squash/ff)
- [ ] P2 Conflict resolution dialog
- [ ] P2 Stash management (create/apply/pop/drop)
- [ ] P2 In‑progress operation banner (cancel/retry)
- [ ] P1 Git identities (name/email, per‑directory)

## 6. Files tab (right)
- [x] P1 File tree (hierarchical, collapsible, filetype icons) — lazy `GET /file?path=`, ignored-file dimming
- [x] P1 File search/filter — fuzzy `GET /find/file?query=`, flat results w/ subpaths
- [x] P1 File viewer with line numbers — read-only monospaced, binary notice, large-file cap
- [ ] ~~P1 Context menu: open / new file / new folder / rename / delete~~ — deferred: opencode file API is **read-only** (no write/create/rename/delete endpoint)
- [ ] ~~P1 File editor (edit + save)~~ — deferred: no write API (agent edits files via tools, not REST)
- [ ] ~~P1 **Autosave vs manual‑save toggle** + dirty indicator + ⌘S~~ — deferred: no write API
- [ ] P2 Syntax highlighting (viewer currently plain monospaced)
- [ ] P2 Multiple open files (tabs, unsaved markers)
- [ ] P2 Find & replace; go‑to‑line
- [ ] P2 Minimap / code folding

## 7. Context tab (right)
- [ ] P1 Context items list (files/attachments/agents/skills) w/ token counts
- [ ] P1 Token‑usage breakdown (system/history/files/total) + bar
- [ ] P1 Context‑limit warning
- [ ] P1 Remove item from context / view file
- [ ] P2 Context modes/tabs (diff/file/context/plan/preview/browser)
- [ ] P2 Plan editor; project notes & todo panel

## 8. Settings
- [ ] P0 **Connection / Remote instances**: add/edit/remove server, auth, verify, switch
- [ ] P0 Providers & API keys (add/verify/remove, masked)
- [ ] P1 Provider OAuth flows
- [ ] P0 Default model / default agent
- [ ] P1 Models: favourites + cycling
- [ ] P1 Agents: list/create/edit/delete (model, prompt, tools, effort)
- [ ] P1 Commands: custom slash commands
- [ ] P1 Skills: list/install/uninstall (catalog + from repo)
- [ ] P1 MCP servers: add/connect/disconnect/remove (+ OAuth)
- [ ] P2 Plugins: install/enable/disable/uninstall
- [ ] P1 Appearance: theme (light/dark/system)
- [ ] P1 Appearance: syntax theme + custom themes (import/export)
- [ ] P1 Appearance: fonts (UI/mono), size, density, radius
- [ ] P1 Chat settings (default model/agent, context length, render mode, limits)
- [ ] P1 Notifications: enable, per‑template text, sound
- [ ] P1 Sessions: retention (archive/delete, period, auto‑cleanup)
- [ ] P1 Keyboard shortcuts: view + customize + conflict detection
- [ ] P1 Git identities editor
- [ ] P2 Behavior: auto‑commit/PR/branch/stash, permission auto‑rules
- [ ] P2 Usage & quota (per‑provider, pace, limits)
- [ ] P2 Voice (TTS/STT)
- [ ] P2 i18n / language selection
- [ ] P2 Tunnel / remote relay configuration

## 9. Terminal
- [ ] P1 Create PTY session (shell picker, cwd)
- [ ] P1 Connect over WebSocket (live I/O)
- [ ] P1 Copy/paste; theme‑matched; font control
- [ ] P2 Multiple terminal tabs

## 10. Connection, sync & realtime
- [ ] P0 `ServerConfig` (baseURL + headers) in Keychain
- [ ] P0 Health probe (`/global/health`)
- [ ] P0 SSE `/event` long‑lived connection + reconnect/backoff
- [ ] P0 Event reducer for all 77 event types (unknown ignored)
- [ ] P1 Multiple servers, quick switch
- [ ] P1 Connection‑status banner / offline handling
- [ ] P2 Workspace/worktree sync endpoints
- [ ] P2 Cert pinning option

## 11. iPad‑native & platform
- [ ] P0 iPad‑only target, landscape + portrait
- [ ] P1 Local notifications (permission/question/idle/error)
- [ ] P1 Hardware keyboard shortcuts
- [ ] P1 Split View / Stage Manager friendliness
- [ ] P1 Share sheet (share session/diff/output)
- [ ] P2 App Intents / Shortcuts
- [ ] P2 Handoff / Continuity
- [ ] P0 Accessibility: Dynamic Type, VoiceOver, contrast, 44pt targets

## 12. Multi‑run & advanced (P2)
- [ ] P2 Multi‑run launcher (multiple sessions/models/branches)
- [ ] P2 Fusion / results comparison
- [ ] P2 Scheduled tasks
- [ ] P2 Session sharing links (view‑only / expiry)
- [ ] P2 Snippets / magic prompts library

---

### Coverage summary
P0 ≈ connection + chat (stream/permissions) + sessions core + git core + shell.
P1 ≈ files/editor, context/token UI, settings depth, terminal, PR/history, notifications.
P2 ≈ multi‑run, plugins, voice, scheduling, advanced git, i18n.
