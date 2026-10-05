#!/usr/bin/env bash
# Patch a deployed Agent Canvas (production build) so the MCP marketplace
# shows the Composio integration with its icon.
#
# Idempotent. Backs up every touched file once (*.bak-composio).
# Rollback: cp <file>.bak-composio <file> for each patched file.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$REPO_DIR/integrations/catalog/composio.json"
ICON="$REPO_DIR/integrations/icons/composio.svg"

CANVAS_ROOT="${CANVAS_ROOT:-/usr/lib/node_modules/@openhands/agent-canvas}"
EXT="$CANVAS_ROOT/node_modules/@openhands/extensions"
CATALOG_DIR="$EXT/integrations/catalog"
ICONS_DIR="$EXT/integrations/icons"
INDEX_JS="$EXT/integrations/catalog-index.js"
AGG_JSON="$EXT/integrations/integration-catalog.json"
PY_AGG="$EXT/python/openhands_extensions/integration-catalog.json"
BUILD_DIR="$CANVAS_ROOT/build"

[ -d "$EXT" ] || { echo "!! extensions package not found at $EXT"; exit 1; }

backup() { [ -f "$1" ] && [ ! -f "$1.bak-composio" ] && cp "$1" "$1.bak-composio" || true; }

# 1. catalog entry + icon into the installed extensions package
cp "$ENTRY" "$CATALOG_DIR/composio.json"
cp "$ICON" "$ICONS_DIR/composio.svg"
echo "✓ installed integrations/catalog/composio.json + icons/composio.svg"

# 2. regenerate catalog-index.js with the upstream generator (if node available)
if command -v node >/dev/null 2>&1; then
  backup "$INDEX_JS"
  ( cd "$EXT" && node scripts/build-integration-catalog.mjs ) \
    && echo "✓ regenerated integrations/catalog-index.js" \
    || echo "!! generator failed; patching index manually"
fi
if ! grep -q "composio.json" "$INDEX_JS" 2>/dev/null; then
  backup "$INDEX_JS"
  python3 - "$INDEX_JS" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
if "composio.json" not in s:
    imports = re.findall(r'import (entry\d+) from "\./catalog/([^"]+)"', s)
    n = len(imports)
    s = s.replace(
        'export const INTEGRATION_CATALOG_ENTRIES = [',
        f'import entry{n} from "./catalog/composio.json" with {{ type: "json" }};\n\nexport const INTEGRATION_CATALOG_ENTRIES = [\n  entry{n},',
        1,
    )
    open(p, "w").write(s)
    print("✓ catalog-index.js patched manually")
PY
fi

# 3. aggregate JSON assets (present in newer extensions builds)
for f in "$AGG_JSON" "$PY_AGG"; do
  if [ -f "$f" ]; then
    backup "$f"
    python3 - "$f" "$CATALOG_DIR/composio.json" <<'PY'
import json, sys
agg, entry = sys.argv[1], sys.argv[2]
data = json.load(open(agg))
e = json.load(open(entry))
items = data if isinstance(data, list) else data.get("entries", data.get("integrations"))
if isinstance(items, list) and not any(x.get("id") == "composio" for x in items):
    items.append(e)
    json.dump(data, open(agg, "w"), indent=2)
    print(f"✓ appended composio to {agg}")
PY
  fi
done

# 4. patch the built frontend bundle (catalog is inlined at build time)
BUNDLE=$(grep -l 'id:`firecrawl`' "$BUILD_DIR"/assets/*.js 2>/dev/null | head -1)
[ -n "$BUNDLE" ] || { echo "!! catalog bundle not found in $BUILD_DIR/assets"; exit 1; }
backup "$BUNDLE"
python3 - "$BUNDLE" "$CATALOG_DIR/composio.json" <<'PY'
import json, sys
bundle, entry = sys.argv[1], sys.argv[2]
s = open(bundle).read()
if "id:`composio`" in s:
    print("✓ bundle already contains composio"); raise SystemExit(0)

def lit(o):
    """JSON value -> minified esbuild object-literal (backticks, bare keys)."""
    if o is True: return "!0"
    if o is False: return "!1"
    if o is None: return "null"
    if isinstance(o, (int, float)): return str(o)
    if isinstance(o, str): return "`" + o.replace("`", "\\`").replace("${", "\\${") + "`"
    if isinstance(o, list): return "[" + ",".join(lit(v) for v in o) + "]"
    if isinstance(o, dict): return "{" + ",".join(f"{k}:{lit(v)}" for k, v in o.items()) + "}"
    raise TypeError(o)

e = lit(json.load(open(entry)))
anchor = "id:`datadog`"
i = s.find(anchor)
if i == -1:
    raise SystemExit("!! anchor entry datadog not found in bundle")
# walk back to the object's opening brace, then forward to its matching close
j = s.rfind("{", 0, i)
depth = 0; k = j
in_str = None
while k < len(s):
    c = s[k]
    if in_str:
        if c == "\\": k += 2; continue
        if c == in_str: in_str = None
    elif c in "`\"'":
        in_str = c
    elif c == "{": depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0: break
    k += 1
obj_end = k + 1
s2 = s[:obj_end] + "," + e + s[obj_end:]
open(bundle, "w").write(s2)
print("✓ built bundle patched with composio entry")
PY

# 4b. make the icon render on THIS deployment: the CDN path only exists after
# the upstream merge, so rewrite logoUrl in the bundle entry to a data URI.
python3 - "$BUNDLE" "$ICON" <<'PY'
import base64, sys
bundle, icon = sys.argv[1], sys.argv[2]
s = open(bundle).read()
needle = "logoUrl:`https://cdn.jsdelivr.net/gh/OpenHands/extensions/integrations/icons/composio.svg`"
if needle not in s:
    print("• bundle logoUrl already localized"); raise SystemExit(0)
data = "data:image/svg+xml;base64," + base64.b64encode(open(icon, "rb").read()).decode()
s = s.replace(needle, "logoUrl:`" + data + "`", 1)
open(bundle, "w").write(s)
print("✓ local bundle logoUrl inlined as data URI")
PY
node --check "$BUNDLE" && echo "✓ bundle syntax OK" || { echo "!! bundle syntax check failed - restoring"; cp "$BUNDLE.bak-composio" "$BUNDLE"; exit 1; }

# 5. syntax-check the patched bundle
node --check "$BUNDLE" && echo "✓ bundle syntax OK" || { echo "!! bundle syntax check failed - restoring"; cp "$BUNDLE.bak-composio" "$BUNDLE"; exit 1; }

echo "Done. Hard-refresh the Canvas UI (Ctrl+Shift+R) to see Composio in the MCP marketplace."
