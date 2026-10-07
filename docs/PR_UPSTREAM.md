# Upstream PR: Composio in the OpenHands integrations catalog

- **PR:** https://github.com/OpenHands/extensions/pull/755
  `feat(integrations): add Composio to the MCP catalog`, branch
  `naoufac:add-composio-integration`, opened 2026-10-07.
- **Linked issue:** https://github.com/OpenHands/extensions/issues/756
  (`ready-for-dev`, labeled by all-hands-bot 2026-10-07).

## What the PR contains

| File | Change |
|---|---|
| `integrations/catalog/composio.json` | Hand-authored catalog entry (shttp, `x-consumer-api-key` header field, `auth.strategy: api_key`) |
| `integrations/icons/composio.svg` | Mark-only icon, official Composio brand mark, black on white, square viewBox |
| `integrations/catalog-index.js` | Regenerated with `npm run build:integrations` |

Source of truth for all three: [`integrations/`](../integrations/) in this repo.

## Verification (run on the PR branch, 2026-10-07)

- `python3 -m pytest tests/test_catalog_schema.py -q` → **87 passed** (entry
  validated against `integrations/catalog.schema.json`, Draft 2020-12)
- `python3 -m pytest tests/test_catalogs.py -q` → **11 passed**
- Import of the regenerated `catalog-index.js` → **80 entries**, `composio`
  resolves with url `https://connect.composio.dev/mcp` + header field
  `x-consumer-api-key`
- Live endpoint: POST `initialize` without key → **401** `Authorization required`
- PR CI on OpenHands/extensions: **all checks green** (PR description validator,
  conventional title, pr-artifacts)

## Upstream contribution flow (learned by doing)

1. Title must be conventional-commit (`feat(...): ...`) or the lint fails.
2. PR description must follow the template: first visible line `HUMAN:`, a
   human note (≥ 20 chars), then `AGENT:`, with `## Why`, `## Summary`,
   `## Issue Number`, `## How to Test`.
3. The description validator requires a linked issue (`Fixes #N`) whose issue
   carries `ready-for-dev` (or predates 2026-08-25). `all-hands-bot` labels
   fresh catalog-addition issues within minutes of opening them.
4. Catalog rule from `AGENTS.md`: exactly one JSON per integration; regenerate
   the index; marketplace fixes belong in this repo, not app-local constants.
