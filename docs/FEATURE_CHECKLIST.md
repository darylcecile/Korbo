# Korbo — Feature Checklist (opencode GUI parity)

Exhaustive catalogue of everything the opencode GUI (openchamber) does, as the
coverage target for the Korbo iPad app. Priorities: **P0** core / **P1** important
/ **P2** later. Checkboxes track implementation (all unchecked at M0).

Legend: `[ ]` not started · `[~]` partial · `[x]` done.

---

## 1. App shell & global layout
- [x] P0 Three‑pane layout: sessions · conversation · context — width-adaptive in `RootView` (GeometryReader → `AppModel.LayoutMode`)
- [x] P0 Collapsible right sidebar (toggle) — `showRightSidebar`, header button + ⌘\
- [x] P1 Resizable panes (drag dividers) with min/max widths — `PaneResizeHandle` on the sessions↔chat and chat↔context dividers; widths clamped (sessions 240–460, context 300–760 and ≤60% of window) and persisted in `UserDefaults`; accent highlight + pointer hover while dragging
- [x] P1 Auto‑collapse right/left at narrow widths (Split View / Stage Manager) — breakpoints compact<720 / medium / wide≥1080; side panes promoted to overlay drawers
- [x] P0 Landscape‑first layout; portrait collapses to center + drawers — compact = chat only with sessions (left) + context (right) overlay drawers; medium = sessions inline + context drawer
- [x] P0 Top bar: model/agent selector, session title, project·branch·diff subtitle — header shows the context ring, session title and project + `+adds/-dels` diff subtitle; model (`modelMenu`) and agent (`agentMenu`) selectors live in the composer footer rather than the top bar; verified on device
- [x] P0 Top bar: context‑usage ring (%) — `contextRing` in ChatPane header: 24pt circular progress ring colored green→amber→red by usage, shows integer %, taps to open the context sidebar; reads `usedTokens`/`contextLimit`; verified on device
- [ ] ~~P1 Top bar: "open in editor" deep link (vscode://, etc.)~~ — deferred: not meaningful on iPad (no desktop editor to receive the deep link)
- [x] P1 Top bar: local/remote (server) selector — server quick-switch menu in the sidebar footer (status dot + active server name); lists saved servers with a checkmark on the active one, switches + reconnects via `switchServer(to:)`, and opens the Connection sheet via "Manage servers…"; verified on device
- [ ] ~~P0 Top bar: account/avatar menu~~ — N/A: opencode servers are unauthenticated (auth is handled by the reverse proxy, configured in the Connection sheet), so there is no account/identity to surface
- [x] P1 Bottom terminal dock (toggle, resize) — repositioned: terminal toggles into the **centre column** (sessions‑toolbar terminal button / ⌘T) so it gets full chat‑pane width; right sidebar can be collapsed from the terminal header to widen it edge‑to‑edge
- [x] P1 Command palette (⌘P): sessions, files, commands, settings, actions — `CommandPalette.swift`, fuzzy file search (`/find/file`), grouped Actions/Sessions/Files, ↑↓ nav + ↵ run + Esc, blurred overlay
- [x] P1 Hardware‑keyboard shortcuts (mirror openchamber set where sensible) — `GlobalShortcuts` in RootView: ⌘P palette, ⌘\ toggle right panel, ⌘1–3 git/files/context, ⌘T toggle terminal, ⌘N new session, ⌘⇧L focus composer, ⌘, settings, ⌘↵ send
- [~] P2 Multi‑window (Stage Manager) — "Open in New Window" session context‑menu action calls `openWindow(value: sessionID)` into a second `WindowGroup(for: String.self)` scene (`SessionWindowView` reusing `ChatPane`); `UIApplicationSupportsMultipleScenes` enabled. The action is wired and activates the requested session (verified on device — selecting it focuses that session's chat); a genuinely separate scene can only render on a physical iPad with Stage Manager / Split View, since the iOS Simulator does not support multiple windows. **v1 limitation (documented in code):** one shared store/selection means the second window mirrors the main window's selected session rather than hosting a fully independent one
- [x] P0 Dark theme baseline; light/system later — app ships a single tuned dark theme (`Theme`); light/system variants deferred

## 2. Sessions sidebar (left)
- [x] P0 Session list with live data from `/session` + events
- [x] P0 Grouping: recent (today/yesterday/7‑days/older)
- [x] P1 Grouping: by project/folder — `SessionGrouping.project` toggle in the sort menu, grouped by `projectName`/`directory`, persisted; already implemented
- [x] P1 Grouping: by worktree/branch — "Worktree" option in the sidebar group-by menu clusters sessions by their full working `directory` (one group per worktree, labelled `<parent>/<leaf>` so multiple worktrees of the same repo stay distinct), ordered by most-recent activity with archived sessions appended. Grouping is by worktree directory rather than git branch: opencode's session API carries `directory` but no per-session branch, and `/vcs` only reports the branch of the server's active directory
- [x] P0 Grouping: archived section
- [x] P0 Item: title, project, +/− diff, relative time *(branch is workspace‑level in opencode, not per‑session — omitted)*
- [~] P1 Item: streaming/active badge *(active dot done; pin/favourite done — see pin/unpin)*
- [x] P0 New session
- [ ] P1 New worktree/branch session
- [x] P0 Search/filter sessions
- [ ] P2 Calendar/activity (by date)
- [x] P0 Context menu: rename
- [x] P0 Context menu: delete (confirm)
- [x] P0 Context menu: archive/unarchive
- [x] P1 Context menu: fork/duplicate — `forkSession` (POST `/session` w/ `parentID`), "Duplicate" context item; verified on device
- [x] P1 Context menu: share (link) / unshare — `shareSession`/`unshareSession`, "Share"/"Copy link"/"Stop sharing" context items; verified on device
- [x] P1 Context menu: pin/unpin — client-local `pinnedSessionIDs` (UserDefaults), `.pinned` bucket renders a "Pinned" group first, pin glyph on rows
- [x] P2 Multi‑select + bulk actions (archive/delete/pin) — toolbar "Select" mode toggle, per‑row selection circles, "N selected" + "Select All"/"Done", bottom bulk bar (Pin/Unpin, Archive/Unarchive, Delete) reusing `setPinned`/`setSessionArchived`/`deleteSession`, delete confirmationDialog; verified on device
- [x] P2 Sort options + project grouping — `SessionGrouping` (recency/project) + `SessionSort` (updated/created/title) menu, persisted; verified on device

## 3. Conversation view (center)
- [x] P0 Message list, user vs assistant distinction — user turns render as right-aligned bubbles, assistant turns left-aligned with a sparkle avatar + model/mode badge; verified on device
- [x] P0 Message header: sender/model logo, model badge, agent badge — each assistant turn shows the model id (e.g. `claude-sonnet-4.6`) plus the agent/mode badge (e.g. `build`/`plan`/`compaction`); verified on device
- [x] P1 Reasoning‑effort/variant badge — `reasoningMenu` brain-icon chip in composer footer shows the active variant (e.g. "Medium"); hidden for non-reasoning models; verified on device
- [x] P0 **Text part**: markdown rendering
- [x] P0 Code blocks: syntax highlighting + copy button
- [x] P0 Markdown: lists, tables, blockquotes, links, emphasis, inline code
- [x] P0 **Reasoning part**: collapsible "thinking" block (streamed) — `ReasoningView` in MessageView renders a chevron-expandable dimmed block per reasoning part; siblings collapse independently; verified on device
- [x] P0 **Tool part**: generic tool call card (name, status, expand)
- [x] P0 Tool: bash/shell command + output (collapsible)
- [x] P0 Tool: edit/write/patch with **diff viewer** (added/removed)
- [x] P1 Tool: read/grep/glob/list rendering
- [x] P1 Tool: task (subagent) nested rendering
- [x] P1 Tool: full‑output modal/expand
- [x] P0 **Todo** list rendering (todowrite/`todo.updated`)
- [x] P0 **File/image attachments** inline (user + assistant)
- [~] P1 Step / snapshot / patch / compaction parts — `compaction` renders as a centered "Context compacted" divider above the summary (verified on device, session `ses_1803cbd07…`); `patch`/`snapshot`/`subtask` render compact defensive markers (build-only — no live data on the server to trigger them); `step-start`/`step-finish` intentionally stay hidden (internal; token/cost already surfaced in footer + usage ring)
- [ ] P0 Per‑message footer: tokens, cost, duration, timestamp
- [x] P0 Message actions: copy — context-menu Copy (long-press) on user + assistant messages, plus inline copy button in the assistant footer with a 1.2s checkmark confirmation; verified on device (clipboard round-trip)
- [x] P1 Message actions: share, fork, revert/unrevert — share (ShareLink), "Fork from here" (POST `/session/{id}/fork` w/ `messageID`), and "Revert to here" (POST `/session/{id}/revert` `{messageID}`, destructive) in the per-message context menu; reverted messages stay in the list but dim to 0.45 opacity, with a top "Reverted — N messages hidden · Undo" banner whose Undo calls POST `/session/{id}/unrevert`; verified on device
- [x] P1 Message actions: delete — destructive "Delete message" (trash) in the per-message context menu opens a "Delete this message?" confirmation dialog; confirm calls DELETE `/session/{id}/message/{messageID}` with optimistic local removal + rollback on error; verified on device (menu + confirmation dialog)
- [x] P1 Session summarize / compact — header compress button (POST `/session/{id}/summarize` `{providerID,modelID,auto}`) triggers a server-side compaction turn; in-flight spinner via `isSummarizing` (POST blocks until compaction completes); verified on device (compaction badge turn started)
- [x] P0 Streaming: incremental text/reasoning/tool deltas — SSE `message.part.updated` → `upsertPart` and `message.part.delta` → `appendDelta` stream text/reasoning/tool output into the live message in place; verified on device (M2)
- [x] P0 Abort/stop active run — composer shows a red `stop.fill` button while a run is active, calling `store.abort()` → `POST /session/{id}/abort`; verified on device
- [x] P0 Inline **permission** card (allow once / always / reject) — `PermissionCard` in ChatPane renders `permission.updated` requests with Allow once / Always / Reject, wired to `replyPermission`; verified on device
- [x] P1 Inline **question** card (reply / reject) — `question.asked` decodes into `pendingQuestions`; `QuestionCard` in ChatPane (mirrors PermissionCard chrome) renders per-question option chips (single/multi-select via FlowLayout) + optional custom TextField, Submit → POST `/question/{requestID}/reply` `{answers:[[label]]}`, Dismiss → POST `/question/{requestID}/reject`; `question.replied`/`question.rejected` events clear the card. Build-verified + render path identical to verified-working permission card; **not yet triggered live on-device** (raised only by the agent's `question` tool, which can't be injected via the read-only SSE stream)
- [x] P0 Empty state — "No messages yet" placeholder plus starter chips shown when a session has no messages and the draft is empty; verified on device
- [x] P0 Error state (+ retry) — connection-failure banner with `lastError` + Retry (see Connection-status banner)
- [ ] P1 Pending‑changes bar (unstaged git) — intentionally dropped (redundant with the git panel)
- [x] P1 Auto‑scroll w/ "scroll to bottom" affordance
- [x] P1 Find in conversation — magnifier button in the chat header reveals a search bar (`X/N` match count, prev/next chevrons, Enter = next, Esc closes); matching messages are highlighted and the list auto-scrolls to the active match; pure client over loaded message parts; verified on device
- [ ] P2 Inline code comments / drafts

## 4. Composer
- [x] P0 Multiline auto‑growing input — `TextField(axis:.vertical)` `lineLimit(1...10)`; Enter sends, Shift+Enter inserts newline (`.onKeyPress(.return)`); verified on device (grew to 3 lines)
- [x] P0 Placeholder "@ for files/agents; / for commands; ! for shell"
- [x] P0 Send (⌘↵) and Stop states — composer send button bound to ⌘↵; Stop (⌘.) aborts while generating
- [x] P0 `@` mention autocomplete: files — debounced fuzzy file search → attachment chip on select; verified on device
- [x] P1 `@` mention autocomplete: agents — `selectableAgents` (`@build`/`@plan`); verified on device
- [x] P1 `/` command/skill autocomplete — first-token `/` filters `store.commands`, inserts `/name `; verified on device
- [x] P1 `!` shell prefix routing — verified on device
- [x] P0 Attach file (document picker)
- [x] P0 Attach image (photo picker) + preview
- [x] P1 Paste image; drag‑drop files — paste verified on device (text + image via UIPasteboard); drag‑drop code-complete (reuses verified attach helpers; cross-app drop unverifiable in headless sim)
- [x] P1 Attachment chips (remove, size/path)
- [x] P0 Model selector — interactive model picker in the composer footer (moved out of header); verified on device (round-trips selection)
- [x] P1 Reasoning‑effort selector — `reasoningMenu` (composer footer) lists the model's variants (descending High→Medium→Low) with a checkmark on the active one; backed by `AppearanceStore`-independent `selectedReasoningVariant` in KorboStore, persisted to UserDefaults, sent as the top-level `variant` field in the prompt body; only shown for models exposing `capabilities.reasoning`; verified on device (select High → persisted across relaunch)
- [x] P0 Agent/mode selector (Build/Plan/…) — agent/mode picker in the composer footer (moved out of header); verified on device
- [x] P1 Draft persistence per session — composer text saved per-session in `AppModel.drafts` (UserDefaults-backed), restored on session switch, cleared on send; verified on device
- [x] P2 Draft preset chips / starters — starter pill chips (Explain codebase, Find & fix a bug, Write unit tests, Review recent changes, Refactor, Add docs) shown when draft empty + no messages; tap prefills + focuses composer, auto‑hides on input; verified on device
- [x] P2 Expand/focus‑mode input — "Enter Full Screen" button opens a `.sheet` "Compose" editor (`TextEditor` bound to same draft, Done collapses keeping text, Send routes through `send()`); draft syncs bidirectionally; verified on device
- [x] P2 Pencil scribble input — "Markup" composer button opens a `PKCanvasView` sketch sheet (pen/eraser/clear, `.anyInput` so finger works in sim); Attach renders the drawing to a PNG and adds it as a removable image `ComposerAttachment` chip; iPadOS Scribble-to-text works natively in the text field; verified on device (drew stroke → Attach enabled → "sketch-1.jpg" chip with thumbnail)

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
- [x] P1 Pull request: create (title/desc/base) — GitHub API; repo picker per session, base/head prefilled from /vcs
- [x] P1 Pull request: view status/reviews/CI — list PRs (state/author/branches) + detail with reviews and check-runs
- [x] P1 Pull request: full-screen diff reviewer — per-file unified diffs (live /pulls/{n}/files), tap-a-line inline comments, existing comments inline, submit review (Comment/Approve/Request changes)
- [ ] P2 Pull request: merge / request review
- [x] P2 Pull request: comment — inline review comments + review-level summary (verified live)
- [ ] P2 Branch integration (merge/rebase/squash/ff)
- [ ] P2 Conflict resolution dialog
- [ ] P2 Stash management (create/apply/pop/drop)
- [ ] P2 In‑progress operation banner (cancel/retry)
- [ ] P1 Git identities (name/email, per‑directory)

## 6. Files tab (right)
- [x] P1 File tree (hierarchical, collapsible, filetype icons) — lazy `GET /file?path=`, ignored-file dimming
- [x] P1 File search/filter — fuzzy `GET /find/file?query=`, flat results w/ subpaths
- [x] P1 File viewer with line numbers — read-only monospaced, binary notice, large-file cap; opens in the **wide centre column** (like the terminal) so it gets full width and can be widened by collapsing the right sidebar; browser stays in the right Files tab; verified on device
- [ ] ~~P1 Context menu: open / new file / new folder / rename / delete~~ — deferred: opencode file API is **read-only** (no write/create/rename/delete endpoint)
- [ ] ~~P1 File editor (edit + save)~~ — deferred: no write API (agent edits files via tools, not REST)
- [ ] ~~P1 **Autosave vs manual‑save toggle** + dirty indicator + ⌘S~~ — deferred: no write API
- [x] P2 Syntax highlighting — dependency-free lexer (`SyntaxHighlighter.swift`), selectable palette (Dark+/Dracula/Solarized/Nord via AppearanceStore.codeTheme), per-extension language detection
- [x] P2 Multiple open files (tabs) — `OpenFile` tab model, tab strip with per-tab close (unsaved markers N/A: viewer is read-only)
- [x] P2 Find & go‑to‑line — find bar (count, prev/next nav, highlight), go-to-line jump (replace N/A: read-only viewer)
- [x] P2 Code folding — indentation-derived fold regions in the file viewer: per-region chevron in the gutter collapses a block to a `⋯ N lines` summary, a toolbar collapse/expand-all button toggles every region, and find / go-to-line auto-reveals any target hidden inside a collapsed region; pure client (language-agnostic, tabs counted as 4 cols); verified on device (collapsed `final class AppModel` body in AppModel.swift). Minimap still pending

## 7. Context tab (right)
- [x] P1 Context items list (files/attachments/agents/skills) w/ token counts — Context tab "Context files" panel lists files/attachments referenced in the conversation (deduped from `file` parts via `store.contextFiles`) with a mime-aware glyph; opencode exposes only aggregate context tokens (shown in the usage bar), not per-item counts, so per-file token counts are intentionally omitted; verified on device
- [x] P1 Token‑usage breakdown (input/cache/output/reasoning) + bar — proportional segmented bar + per-bucket legend from the latest assistant turn's `tokens`; verified on device
- [x] P1 Context‑limit warning — total vs model `limit.context` with % and an amber warning at ≥80%; verified on device (200K window resolved)
- [~] P1 Remove item from context / view file — view: context-file rows are now tappable; image attachments open an inline base64-decoded preview sheet, text files open in the Files center pane (verified on device with `korbo-test.png`). Remove-from-context still pending (needs server support)
- [x] P2 Context modes/tabs — segmented **Files / Plan / Usage** `Picker` at the top of the Context tab splits existing context data into sub-modes (Files = files-in-context list w/ tap-to-view; Plan = agent todo/plan panel; Usage = cost + token-usage breakdown + diff stats + model/project); pure client reorg over already-loaded data (no new networking); verified on device
- [x] P1 Agent todo panel — Context tab "Agent todos" panel reads the latest `todowrite`/`todoread` tool part (`store.latestTodos`), showing completed/total progress + per-row glyph (half-circle for in-progress accent, struck-through green when completed) and priority; hidden when empty; verified on device
- [ ] P2 Plan editor; project notes & todo panel

## 8. Settings — M6 delivered (SettingsView + ChatPane pickers)
- [x] P0 **Connection / Remote instances**: add/edit/remove server, auth, verify, switch — Connection section + "Change server…" → ConnectionSheet (multi-server, keychain)
- [x] P0 Providers & API keys (add/verify/remove, masked) — connected-first list + "All providers (N)" disclosure; ⋯ menu → Add/Replace key (SecureField) `PUT /auth/{id}` + Remove `DELETE /auth/{id}`. NOTE: opencode's `connected` reflects genuinely usable providers, so a bogus key won't flip the badge (verified at API-contract level).
- [ ] P1 Provider OAuth flows — deferred (needs `POST /provider/{id}/oauth/authorize|callback` device-flow UI)
- [x] P0 Default model / default agent — ChatPane header `modelMenu` (Auto + per-connected-provider model sections, checkmarks) + `agentMenu` (build/plan, hidden+subagent filtered); persisted to UserDefaults; sent per-prompt as `model`/`agent`
- [ ] P1 Models: favourites + cycling — deferred (not API-backed)
- [ ] P1 Agents: list/create/edit/delete (model, prompt, tools, effort) — read-only catalogue delivered (name + primary/subagent badge + description); create/edit/delete deferred (opencode configures agents via config file, no REST CRUD)
- [ ] P1 Commands: custom slash commands — read-only catalogue delivered (`/name` + description via `GET /command`); CRUD deferred (config-file only)
- [ ] P1 Skills: list/install/uninstall (catalog + from repo) — deferred (no REST API)
- [ ] P1 MCP servers: add/connect/disconnect/remove (+ OAuth) — deferred (config-file only)
- [ ] P2 Plugins: install/enable/disable/uninstall — deferred (config-file only)
- [x] P1 Appearance: theme (light/dark/system) — `AppearanceStore` with Dark/Midnight dark variants (no light theme — app is dark-only by design) + 6 accent colors (amber/blue/green/purple/pink/graphite); `Theme` tokens are now computed from the store, RootView is keyed by `accent-theme` so all static `Theme.*` reads re-resolve live; Settings → Appearance section with accent swatches + segmented theme picker; verified on device (accent + theme change propagate app-wide including message rows, both directions)
- [~] P1 Appearance: syntax theme + custom themes (import/export) — selectable code theme in Settings → Appearance (Dark+, Dracula, Solarized, Nord) with an official-palette per scheme; resolves through `CodeTokenKind.color` so chat code blocks + the file viewer recolour live (verified on device with project.yml → Dracula); persisted to UserDefaults. Custom theme import/export still pending
- [~] P1 Appearance: fonts (UI/mono), size, density, radius — text-size (Small/Standard/Large/X-Large via `dynamicTypeSize`) + density (Comfortable/Compact) pickers added in Settings; effect limited to Dynamic-Type-respecting text/controls since most app fonts are hardcoded `.system(size:)` (documented in the Settings footer note); custom font family + radius still pending
- [~] P1 Chat settings (default model/agent, context length, render mode, limits) — new Settings → Chat section: "Render markdown" toggle (off ⇒ assistant `.text` parts render as raw selectable monospaced source; `MessageView` observes `AppearanceStore` so it recolours live — verified on device flipping the Alpha compaction summary to raw `## Goal` markdown) persisted to UserDefaults; default model + default agent surfaced read-only (sourced from composer pickers). Context length + per-session limits still pending
- [ ] P1 Notifications: enable, per‑template text, sound
- [~] P1 Sessions: retention — swipe-to-archive (leading, `PATCH /session/{id}` `time.archived`) and swipe-to-delete (trailing, routed through the destructive confirmation dialog → `DELETE /session/{id}`) on session rows; sidebar converted to a `List` to host the swipe actions; both API-backed; verified on device. Retention period / auto-cleanup still pending
- [~] P1 Keyboard shortcuts: view (⌘/ cheat sheet + command-palette "Keyboard Shortcuts" action; grouped Navigation/Panels/Session/App with key chips). Customize + conflict detection still pending.
- [ ] P1 Git identities editor
- [ ] P2 Behavior: auto‑commit/PR/branch/stash, permission auto‑rules
- [ ] P2 Usage & quota (per‑provider, pace, limits)
- [x] P2 Voice (TTS/STT) — `SpeechController` singleton: read-aloud speaker button in each assistant message footer (`AVSpeechSynthesizer`, toggles per-message, delegate resets state on finish/cancel) + composer mic button for live dictation (`SFSpeechRecognizer` + `AVAudioEngine`, partial transcripts stream into the draft); mic + speech Info.plist usage keys added. Verified on device: TTS button present/wired; mic triggers the Microphone permission prompt + flow. Live transcription requires real-device mic (simulator has no microphone)
- [ ] P2 i18n / language selection
- [ ] P2 Tunnel / remote relay configuration

## 9. Terminal
- [x] P1 Create PTY session (shell picker, cwd) — `POST /pty`, `GET /pty/shells` shell menu
- [x] P1 Connect over WebSocket (live I/O) — `ws://host/pty/{id}/connect`, SwiftTerm renderer, live ANSI colors + bidirectional stdin
- [x] P1 Copy/paste; theme‑matched; font control — SwiftTerm input-accessory keyboard, monospaced font, dark theme‑matched
- [x] P2 Multiple terminal tabs — header tab strip over running PTYs, "+" spawns new, trash kills
- [x] P1 Terminal in centre column — sessions‑toolbar terminal toggle (⌘T) swaps chat→terminal for full width; right‑sidebar collapse toggle in the terminal header widens it edge‑to‑edge; selecting a session returns to chat
- Deferred: pinch-to-zoom font sizing, persistent scrollback search (not exposed by opencode PTY API)

## 10. Connection, sync & realtime
- [x] P0 `ServerConfig` (baseURL + headers) in Keychain — `ServerConfig` persists in UserDefaults with the secret (basic-auth password / bearer token) in the Keychain via `Keychain`; verified on device
- [x] P0 Health probe (`/global/health`) — `connect()` calls `client.health()` and only flips to Connected on success; verified on device
- [x] P0 SSE `/event` long‑lived connection + reconnect/backoff — `startEventStream` holds the `/event` stream with reconnect/backoff; verified on device (live streaming)
- [x] P0 Event reducer for all 77 event types (unknown ignored) — `OCEventType` enum + the store's event handler reduce the known events; unknown types decode to `.unknown` and are ignored; verified on device
- [x] P1 Multiple servers, quick switch — `ServerStore` persists multiple servers; the sidebar-footer menu switches the active one and reconnects (`switchServer(to:)`); verified on device
- [x] P1 Connection‑status banner / offline handling — top banner surfaces connecting/failed/disconnected with `lastError` detail + one-tap Retry; hidden while connected; verified on device
- [ ] P2 Workspace/worktree sync endpoints
- [ ] P2 Cert pinning option

## 11. iPad‑native & platform
- [x] P0 iPad‑only target, landscape + portrait — XcodeGen target is iPad-only and the adaptive shell supports landscape + portrait; verified on device
- [ ] P1 Local notifications (permission/question/idle/error)
- [x] P1 Hardware keyboard shortcuts — global ⌘-shortcuts via `GlobalShortcuts` (palette, panel toggles, tab switches, new session, focus composer, settings, send)
- [x] P1 Split View / Stage Manager friendliness — width-driven adaptive 3/2/1-pane shell with auto-collapsing side panels + overlay drawers
- [x] P1 Share sheet (share session/diff/output) — session context menu "Share link" shares the opencode share URL via the native iOS share sheet (`UIActivityViewController` wrapped in `ActivityView`, presented with an `Identifiable` `ShareURLItem`); verified on device (rich link preview, Copy/More)
- [x] P2 App Intents / Shortcuts — `NewSessionIntent` + `SendPromptIntent` (String prompt param) with `KorboShortcuts: AppShortcutsProvider` phrases; `IntentRouter` singleton holds a pending action (`openAppWhenRun`), `KorboApp` observes via `.onChange` and dispatches to the store (connect → create session if needed → create/send). Build-level verified (`Metadata.appintents` generated); Siri/Shortcuts invocation not drivable in the simulator
- [ ] P2 Handoff / Continuity
- [~] P0 Accessibility: Dynamic Type, VoiceOver, contrast, 44pt targets — VoiceOver labels added across all panels (icon-only controls labelled, decorative glyphs hidden; verified in the live a11y tree). Dynamic Type and strict 44pt hit-targets deliberately deferred: the layout uses fixed point fonts tuned for compact density, so scaled-font/44pt reflow is a larger refactor tracked separately

## 12. Multi‑run & advanced (P2)
- [ ] P2 Multi‑run launcher (multiple sessions/models/branches)
- [ ] P2 Fusion / results comparison
- [ ] P2 Scheduled tasks
- [ ] P2 Session sharing links (view‑only / expiry)
- [x] P2 Snippets / magic prompts library — `SnippetStore` singleton (UserDefaults-persisted, seeds 4 defaults) + "Bookmark" composer button opening a sheet (app-native `ScrollView`+`LazyVStack` rows, per-row ⋯ menu for Edit/Move Up/Move Down/Delete + long-press context menu, add/edit form); tapping a snippet inserts its text into the composer draft and dismisses. Verified on device (tapped "Explain selection" → draft populated + Send enabled)

---

### Coverage summary
P0 ≈ connection + chat (stream/permissions) + sessions core + git core + shell.
P1 ≈ files/editor, context/token UI, settings depth, terminal, PR/history, notifications.
P2 ≈ multi‑run, plugins, voice, scheduling, advanced git, i18n.
