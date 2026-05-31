# opencode API Reference (for the Korbo iPad client)

> Source of truth: `packages/sdk/openapi.json` in the opencode repo
> (`github.com/anomalyco/opencode`). This document distills the parts the Korbo
> client needs. Verified against the OpenAPI 3.1 spec (292 schemas, ~110 paths)
> and the server source on 2026-05-31.

## 1. Connection & runtime model

- **Server**: started with `opencode serve`. Default bind is
  `http://127.0.0.1:4096` (source: `packages/opencode/src/server/server.ts` tries
  port `4096`, then a free port; `packages/opencode/src/cli/network.ts` default
  hostname `127.0.0.1`).
- **LAN exposure**: `--hostname 0.0.0.0` or `--mdns` (advertises `opencode.local`).
- **Auth**: the server has **no built-in authentication** (no `securitySchemes`
  in the spec). It is localhost-trusted by design.
- **Remote/iPad implication**: do **not** expose the raw server to the internet.
  Put it behind a reverse proxy (TLS + bearer/basic auth) or an SSH/relay tunnel.
  Korbo sends credentials via per-server custom `headers`. openchamber documents
  the same pattern (`docs/REVERSE_PROXY.md`, `docs/PREVIEW_REMOTE_RELAY.md`).
- **Transport**: REST + JSON. Live updates via **SSE** at `GET /event`. Terminal
  I/O via **WebSocket** at `GET /pty/{ptyID}/connect`.
- **ID prefixes**: `ses_` session, `msg_` message, `prt_` part, `per_` permission,
  `wrk_` workspace, `pty_` pty.

## 2. HTTP endpoints (by area)

### Health / global / instance
- `GET /global/health` — health probe
- `GET/PATCH /global/config` — global configuration
- `GET /global/event` — global event stream
- `POST /global/upgrade` — upgrade opencode
- `POST /global/dispose`, `POST /instance/dispose` — teardown
- `GET /path` — resolved paths
- `GET /project`, `GET /project/current`, `PATCH /project/{projectID}`,
  `POST /project/git/init`
- `POST /log` — write a log line

### Sessions
- `GET /session` — list (query: `workspaceID`, `directory`, `project`, `search`,
  `limit`, `order`, `cursor`)
- `POST /session` — create
- `GET/DELETE/PATCH /session/{sessionID}`
- `GET /session/status`, `GET /session/{sessionID}` — status/detail
- `GET /session/{sessionID}/children` — child/forked sessions
- `POST /session/{sessionID}/fork`
- `POST /session/{sessionID}/init` — initialize (AGENTS.md etc.)
- `POST /session/{sessionID}/abort`
- `POST /session/{sessionID}/summarize`
- `POST /session/{sessionID}/revert`, `POST /session/{sessionID}/unrevert`
- `POST/DELETE /session/{sessionID}/share`
- `GET /session/{sessionID}/diff` — diff for a message
- `GET /session/{sessionID}/todo` — session todo list
- `POST /session/{sessionID}/command` — run a command
- `POST /session/{sessionID}/shell` — run a shell command in session context

### Messages & parts
- `GET /session/{sessionID}/message` — list (query: `limit`, `cursor`, `order`)
- `POST /session/{sessionID}/message` — send (synchronous-style)
- `POST /session/{sessionID}/prompt_async` — **send & stream** (recommended; reply
  arrives over `/event`)
- `GET/DELETE /session/{sessionID}/message/{messageID}`
- `DELETE/PATCH /session/{sessionID}/message/{messageID}/part/{partID}`

**Prompt body** (`POST .../message` and `.../prompt_async`):
```jsonc
{
  "messageID": "msg_…",            // optional, client-supplied id
  "model": { "providerID": "anthropic", "modelID": "claude-…" },
  "agent": "build",                // optional
  "system": "…",                   // optional system override
  "variant": "…",                  // reasoning variant
  "tools": { "bash": true },       // optional per-tool enable/disable
  "noReply": false,
  "parts": [
    { "type": "text", "text": "hello" },
    { "type": "file", "mime": "image/png", "filename": "a.png", "url": "data:…" },
    { "type": "agent", "name": "…" },
    { "type": "subtask", "…": "…" }
  ]
}
```

### Permissions & questions (interaction)
- `GET /permission` — pending permission requests
- `POST /permission/{requestID}/reply` — `{ approved: bool }` (or once/always)
- `POST /session/{sessionID}/permissions/{permissionID}` — session-scoped reply
- `GET /question` — pending questions
- `POST /question/{requestID}/reply`, `POST /question/{requestID}/reject`

### Providers, models, agents, commands, skills, config
- `GET /provider`, `GET /api/provider`, `GET /api/provider/{providerID}`
- `GET /provider/auth` — supported auth methods
- `PUT/DELETE /auth/{providerID}` — set/remove credentials (oauth | api key)
- `POST /provider/{providerID}/oauth/authorize`, `.../oauth/callback`
- `GET /api/model` — models
- `GET /agent` — agents
- `GET /command` — slash commands
- `GET /skill` — skills
- `GET/PATCH /config`, `GET /config/providers`

### Files, search, formatting, LSP
- `GET /file` — list files
- `GET /file/content` — read file (query: `path`)
- `GET /file/status` — git status of a path (`added|deleted|modified` + counts)
- `GET /find` — ripgrep text search
- `GET /find/file` — fuzzy file search
- `GET /find/symbol` — LSP workspace symbols
- `GET /formatter`, `GET /lsp` — tooling status

### VCS / git
- `GET /vcs` — repo info
- `GET /vcs/status` — working-tree status
- `GET /vcs/diff`, `GET /vcs/diff/raw` — diffs
- `POST /vcs/apply` — apply a patch

### Workspaces & worktrees (experimental)
- `GET/POST /experimental/workspace`, `GET .../status`, `GET .../adapter`,
  `POST .../sync-list`, `POST .../warp`, `DELETE .../{id}`
- `GET/POST/DELETE /experimental/worktree`, `POST .../reset`
- `GET /experimental/session`, `GET /experimental/tool`, `GET /experimental/tool/ids`,
  `GET /experimental/resource`
- Sync: `POST /sync/start`, `/sync/history`, `/sync/replay`, `/sync/steal`

### MCP
- `GET/POST /mcp`, `POST /mcp/{name}/connect`, `POST /mcp/{name}/disconnect`
- `POST/DELETE /mcp/{name}/auth`, `.../auth/authenticate`, `.../auth/callback`

### Terminal (PTY)
- `GET/POST /pty`, `GET /pty/shells`
- `GET/PUT/DELETE /pty/{ptyID}`
- `GET /pty/{ptyID}/connect` (WebSocket), `POST /pty/{ptyID}/connect-token`

### TUI bridge (drive a running TUI; mostly N/A for Korbo)
- `POST /tui/*` (append/submit/clear prompt, execute-command, open dialogs,
  show-toast, select-session), `GET /tui/control/next`, `POST /tui/control/response`

## 3. Event stream (`GET /event`, SSE)

77 event types. Each frame is `data: { "type": "…", "properties": { … } }`.
The ones Korbo must handle for a live conversation:

**Session lifecycle**: `session.created`, `session.updated`, `session.deleted`,
`session.status`, `session.idle`, `session.error`, `session.compacted`,
`session.diff`.

**Messages/parts**: `message.updated`, `message.removed`, `message.part.updated`,
`message.part.removed`, `message.part.delta`.

**Streaming pipeline ("next")**: `…prompted`, `…synthetic`, `…step.started/ended/failed`,
`…text.started/delta/ended`, `…reasoning.started/delta/ended`,
`…tool.input.started/delta/ended`, `…tool.called`, `…tool.progress`,
`…tool.success`, `…tool.failed`, `…shell.started/ended`, `…retried`,
`…compaction.started/delta/ended`, `…agent.switched`, `…model.switched`.

**Interaction**: `permission.asked`, `permission.replied`, `question.asked`,
`question.replied`, `question.rejected`, `todo.updated`.

**Workspace/VCS/tooling**: `file.edited`, `file.watcher.updated`,
`vcs.branch.updated`, `project.updated`, `lsp.updated`, `mcp.tools.changed`,
`command.executed`, `workspace.ready/failed/status`, `worktree.ready/failed`.

**PTY**: `pty.created`, `pty.updated`, `pty.exited`, `pty.deleted`.

**Server/account/install**: `server.connected`, `installation.updated`,
`installation.update-available`, `account.added/removed/switched`,
`global.disposed`, `server.instance.disposed`.

## 4. Core data models (selected fields)

**Session**: `id, slug, projectID, workspaceID, directory, path, parentID,
summary{additions,deletions,files,diffs}, cost, tokens{input,output,reasoning,
cache{read,write}}, share{url}, title, agent, model{providerID,modelID,variant?},
version, time{created,updated,compacting?,archived?}, permission, revert{…}`.

**UserMessage**: `id, sessionID, role:"user", time, agent, model, system, tools,
summary, format`.

**AssistantMessage**: `id, sessionID, role:"assistant", time{created,completed?},
error?, parentID, modelID, providerID, mode, agent, path{cwd,root}, cost,
tokens, variant, finish`.

**Part** (union): `TextPart`, `ReasoningPart`, `FilePart`, `ToolPart`,
`StepStartPart`, `StepFinishPart`, `SnapshotPart`, `PatchPart`, `AgentPart`,
`SubtaskPart`, `RetryPart`, `CompactionPart`. Common fields: `id, sessionID,
messageID, type`. `TextPart.text`, `ReasoningPart.text`,
`FilePart{mime,filename,url,source}`, `ToolPart{callID,tool,state}`.

**ToolState** (union, `status`): `pending{input}`, `running{input,content}`,
`completed{input,content,structured,attachments?}`, `error{input,error}`.

**Provider**: `id, name, source:"env"|"config"|"custom"|"api", env[], key,
options, models{modelID:Model}`.

**Model**: `id, providerID, name, family, capabilities, cost, limit,
status:"alpha"|"beta"|"deprecated"|"active", release_date, variants`.

**Agent**: `name, description, mode:"primary"|"subagent"|"all", model, prompt,
temperature, topP, color, permission, steps, hidden, native`.

**Command**: `name, description, agent, model, source:"command"|"mcp"|"skill",
template, subtask, hints[]`.

**Todo**: `content, status, priority`.

**File (status)**: `path, added, removed, status:"added"|"deleted"|"modified"`.

## 5. Built-in tools (rendered as ToolPart)

`bash`, `edit`, `write`, `read`, `grep`, `glob`, `list`, `webfetch`, `task`
(subagent), `todowrite`, `todoread`, `patch`. MCP/skill tools appear dynamically.

## 6. Recommended client flow (Korbo)

1. Configure a `ServerConfig` (baseURL + auth headers). Probe `GET /global/health`.
2. Open one long-lived `GET /event` SSE connection (with `directory`/`workspace`
   filters); reconnect with backoff.
3. List sessions/messages via REST; render from event deltas thereafter.
4. Send prompts with `POST /session/{id}/prompt_async`; stream the reply from
   `…text.delta` / `…reasoning.delta` / `…tool.*` events.
5. On `permission.asked` / `question.asked`, present inline UI and reply via REST.
6. Git/files panels read `/vcs/*`, `/file/*`, `/session/{id}/diff`.
7. Terminal opens a PTY and connects over WebSocket.
