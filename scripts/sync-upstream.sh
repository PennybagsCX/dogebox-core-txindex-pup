#!/usr/bin/env bash
# Re-syncs this fork with the upstream Dogebox-WG `core` pup, re-applying the txindex patch.
# Run locally or via .github/workflows/sync-upstream.yml (weekly).
# Idempotent: exits 0 with "no changes" if upstream hasn't moved.
set -euo pipefail

UPSTREAM_REPO="https://github.com/Dogebox-WG/pups.git"
PUP_DIR="core-txindex"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> Fetching upstream core pup..."
if ! git clone --depth 1 -q "$UPSTREAM_REPO" "$WORK/pups"; then
  echo "!! Failed to clone upstream"; exit 1
fi

UP_CORE="$WORK/pups/core"
OUR_PUP_NIX="$PUP_DIR/pup.nix"
OUR_MANIFEST="$PUP_DIR/manifest.json"

# Bail early if upstream core is unchanged since last sync (unless forced)
UP_SHA=$(git -C "$WORK/pups" rev-parse HEAD:core)
LAST_SHA=$(cat .upstream-sha 2>/dev/null || echo "")
if [ "$UP_SHA" = "$LAST_SHA" ] && [ "${1:-}" != "--force" ]; then
  echo ">> Upstream unchanged ($UP_SHA). Nothing to do."
  exit 0
fi

echo ">> Upstream core changed ($LAST_SHA -> $UP_SHA). Applying txindex patch..."

# 1. Take upstream pup.nix verbatim, then insert -txindex=1 before the zmq line
#    (upstream always passes -zmqpubhashblock last in the core pup's flags).
if ! grep -q -- '-zmqpubhashblock=tcp://0.0.0.0:28332' "$UP_CORE/pup.nix"; then
  echo "!! Upstream pup.nix no longer contains the expected zmq flag — manual review needed."; exit 1
fi
if grep -q -- '-txindex' "$UP_CORE/pup.nix"; then
  echo ">> Upstream now ships txindex natively — fork may be retired. Manual review needed."; exit 1
fi
sed 's|\(-zmqpubhashblock=tcp://0.0.0.0:28332\)|-txindex=1 \\\n      \1|' \
  "$UP_CORE/pup.nix" > "$OUR_PUP_NIX"

# 2. Refresh ancillary assets wholesale (monitor/logger may change upstream).
#    NOTE: logo.png is intentionally NOT synced — this repo carries a custom logo.
for asset in monitor logger; do
  rm -rf "$PUP_DIR/$asset"
  cp -R "$UP_CORE/$asset" "$PUP_DIR/$asset"
done

# 3. Update manifest: hash of new pup.nix + upstream version metadata.
#    Keeps our name/description; bumps patch version.
NEW_HASH=$(sha256sum "$OUR_PUP_NIX" | cut -d' ' -f1)
python3 - "$OUR_MANIFEST" "$NEW_HASH" "$UP_CORE/manifest.json" <<'EOF'
import json, re, sys
ours_path, new_hash, upstream_path = sys.argv[1], sys.argv[2], sys.argv[3]
ours = json.load(open(ours_path))
up = json.load(open(upstream_path))
ours['container']['build']['nixFileSha256'] = new_hash
if up['meta'].get('upstreamVersions'):
    ours['meta']['upstreamVersions'] = up['meta']['upstreamVersions']
m = re.match(r'^(\d+)\.(\d+)\.(\d+)$', ours['meta']['version'])
if m:
    ours['meta']['version'] = f"{m[1]}.{m[2]}.{int(m[3]) + 1}"
json.dump(ours, open(ours_path, 'w'), indent=2)
print("manifest updated: version", ours['meta']['version'], "hash", new_hash[:12])
EOF

echo "$UP_SHA" > .upstream-sha

if git diff --quiet -- "$PUP_DIR" 2>/dev/null; then
  echo ">> Applied patch but result is identical to what we had. Updating marker only."
else
  echo ">> Fork updated. Review, commit, tag (semver!), and push:"
  echo "   git add -A && git commit -m 'sync upstream core' && git tag vX.Y.Z && git push --tags origin main"
fi
