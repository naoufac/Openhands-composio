# Composio × OpenHands — Integration Inspection Report

**Date:** 2026-10-05
**Scope:** the Composio integration as deployed on this Agent Canvas host, the
OpenHands integration catalog it should appear in, and the fixes needed to make
Composio a first-class citizen.

---

## 1. What the integration actually is

There is no Composio *code* on this host. The integration is a **remote MCP
(server) connection**:

```
$OPENHANDS_HOME/settings.json
└── agent_settings.mcp_config.composio
    ├── url:       https://connect.composio.dev/mcp
    ├── transport: http          (streamable HTTP / "shttp")
    ├── headers:   x-consumer-api-key: <encrypted secret>
    └── enabled:   true
```

At conversation start, Agent Canvas passes this MCP config to the agent server,
which opens a streamable-HTTP MCP session to Composio's hosted gateway
("Composio Connect"). Composio exposes a set of **meta-tools** (tool search,
tool execution, connection management, skills, feedback, workbench) instead of
one tool per app. Those meta-tools become callable agent tools prefixed
`composio_*`.

### Verified live

During this inspection the following calls succeeded *through the configured
integration* (proof the connection is healthy):

- `COMPOSIO_SEARCH_TOOLS` — plan/​toolkit discovery over Composio's index
  (returned active `firecrawl` (private) and `exa` (instant) connections)
- `GITHUB_*` tools in this conversation also route via MCP (GitHub Copilot MCP)

Remaining config remnants (not part of the runtime path):

- `/opt/canvas-openhands/.composio/user_data.json` — `{"api_key": null}` (empty
  CLI state; the Composio CLI is not used by this deployment)

## 2. Official source of truth (cross-checked)

From Composio's docs, **"Connect with MCP"**
(<https://docs.composio.dev/docs/composio-connect>):

> "Composio Connect is an MCP server at `https://connect.composio.dev/mcp` that
> gives your AI agent access to 1000+ apps ... through a single connection."

The same page documents header auth for MCP clients that support custom
headers:

> "choose *Custom headers*, then set `x-consumer-api-key` to ..."

This exactly matches the deployed configuration — the local settings are
correct and canonical. API keys are managed at
<https://platform.composio.dev> (Settings → API Keys).

Related Composio endpoints (documented, **not** used here):

- `https://backend.composio.dev/v3/mcp/{server_id}` — per-session /
  single-toolkit MCP servers (SDK-driven)
- `https://mcp.composio.dev/mcp` — redirects to the marketing page; **not** an
  endpoint

## 3. Architecture (how it flows)

```
Agent Canvas (browser)
   │  settings: mcp_config.composio
   ▼
agent-server (OpenHands SDK runtime, :18100)
   │  MCP client (streamable HTTP)
   ▼
connect.composio.dev/mcp  ──►  Composio Connect gateway
   │                              │
   │  meta-tools: search/execute/ │  OAuth'd app connections
   │  manage/skills/feedback/     │  (Gmail, Slack, GitHub, …)
   ▼  workbench                   ▼
agent tool calls             500+ SaaS apps
```

Key properties:

- **One MCP connection → many apps.** Composio brokers per-app OAuth; the agent
  only ever sees Composio's meta-tools.
- **Keys never touch the agent.** The consumer API key is stored encrypted in
  OpenHands settings and injected as a header by the MCP client.
- **Tool sets are dynamic.** `COMPOSIO_SEARCH_TOOLS` returns a per-task plan;
  tools execute via `COMPOSIO_MULTI_EXECUTE_TOOL` (up to 50 parallel, only
  independent calls batched).

## 4. What needed fixing

### Gap 1 — Composio is missing from the integrations catalog

The Agent Canvas **MCP marketplace** (settings → MCP) is rendered from
`@openhands/extensions` → `integrations/catalog/*.json` (79 entries at
inspection time). There is **no `composio.json`**, so:

- Composio cannot be installed from the marketplace UI; only manual JSON edits
  (what this host originally did) work.
- Any manually-added Composio server renders with the **generic puzzle-piece
  fallback icon** (see `McpLogoBadge` in agent-canvas: `fallback: Puzzle`),
  with no description, docs link, or install hints.

**Fix:** add `integrations/catalog/composio.json` (+ `integrations/icons/composio.svg`)
— included in this repo and proposed upstream.

### Gap 2 — the catalog is inlined in the built frontend bundle

The marketplace reads the catalog at **build time** (static ESM imports), not
from a runtime API. The catalog entries are inlined inside
`build/assets/vendor~root-layout~…-DAygCsCR.js`. So fixing the live UI on a
deployed (production build) Canvas requires patching that bundle as well as the
installed `node_modules` copy. Both are handled by `scripts/patch-local-canvas.sh`
(reversible; `.bak` backups).

## 5. The icon

- Source: official Composio logo `https://composio.dev/logos/composio-full-black.svg`
  (served by composio.dev; GitHub org avatar at `github.com/composiohq` is the
  same mark).
- The full logo is a 483×93 wordmark+mark; the **mark-only paths** (first two
  `<path>` elements) were extracted and re-centered into a tight square
  viewBox (`-10.544 -4.431 97.564 97.564`) with the original
  `stroke-width 2.53542` and round caps/joins preserved.
- Per the requirement, the badge uses a **white background** (`iconBg:
  "#FFFFFF"`) with the black Composio mark — matching how Slack/Salesforce
  entries pair a flat badge color with a single-color mark.

## 6. Configuration reference

| Field | Value |
|---|---|
| MCP URL | `https://connect.composio.dev/mcp` |
| Transport | streamable HTTP (`shttp`) |
| Auth header | `x-consumer-api-key: <consumer API key>` |
| Key management | <https://platform.composio.dev> → Settings → API Keys |
| App connections | <https://platform.composio.dev> → Apps (per-app OAuth) |
| Docs | <https://docs.composio.dev/docs/composio-connect> |
| Dashboard/org | <https://dashboard.composio.dev> |

## 7. Verification transcript

| Check | Result |
|---|---|
| MCP endpoint reachable (no auth) | `{"error":"Authorization required"}` → endpoint up, auth enforced ✔ |
| Local settings match official docs | url + header identical ✔ |
| Live tool call via integration | `COMPOSIO_SEARCH_TOOLS` returned plan + 2 active toolkits ✔ |
| Catalog entry schema | Draft 2020-12 validation against upstream `catalog.schema.json` ✔ |
| Icon SVG | well-formed XML, mark-only, square viewBox, ≤2 KB ✔ |
| Marketplace UI (after local patch) | see `assets/screenshot.png` ✔ |

## 8. Files in this repo

```
integrations/catalog/composio.json   # catalog entry (schema-valid)
integrations/icons/composio.svg      # mark-only icon, black on white
scripts/patch-local-canvas.sh        # idempotent local deployment patch
assets/screenshot.png                # marketplace showing Composio w/ icon
docs/INSPECTION.md                   # this file
docs/PR_UPSTREAM.md                  # the PR opened to OpenHands/extensions
```
