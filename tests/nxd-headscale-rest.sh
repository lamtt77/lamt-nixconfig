#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/timing.sh"
nxd_test_timing_wrap "$0" "$@"
# Live Headscale REST smoke for LAMT (requires HEADSCALE_API_ORIGIN + HEADSCALE_API_TOKEN).
#
# Never prints the token. Optional private env file (not in git):
#   ~/.config/nxd/headscale.env  (export HEADSCALE_API_ORIGIN / HEADSCALE_API_TOKEN)
#
# Usage:
#   ./tests/nxd-headscale-rest.sh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

if [[ -f "${HOME}/.config/nxd/headscale.env" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.config/nxd/headscale.env"
fi

: "${HEADSCALE_API_ORIGIN:?set HEADSCALE_API_ORIGIN (https origin, e.g. https://ts.lamhub.com)}"
: "${HEADSCALE_API_TOKEN:?set HEADSCALE_API_TOKEN (API bearer; never commit)}"

if [[ "${HEADSCALE_API_ORIGIN}" != https://* ]]; then
  echo "ERROR: HEADSCALE_API_ORIGIN must use https" >&2
  exit 1
fi

export HEADSCALE_API_ORIGIN HEADSCALE_API_TOKEN
echo "Headscale REST smoke origin=${HEADSCALE_API_ORIGIN} token_len=${#HEADSCALE_API_TOKEN}"

python3 - <<'PY'
import json, os, sys, urllib.request
from datetime import datetime, timedelta, timezone

origin = os.environ["HEADSCALE_API_ORIGIN"].rstrip("/")
token = os.environ["HEADSCALE_API_TOKEN"]

def req(method, path, data=None):
    body = None if data is None else json.dumps(data).encode()
    r = urllib.request.Request(
        origin + path,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(r, timeout=20) as resp:
        raw = resp.read()
        return resp.status, (json.loads(raw) if raw else {})

failures = []

try:
    code, ver = req("GET", "/version")
    assert code == 200 and ver.get("version"), ver
    print(f"OK version={ver.get('version')}")
except Exception as e:
    failures.append(f"version: {e}")

try:
    code, users = req("GET", "/api/v1/user")
    ulist = users.get("users") or []
    assert code == 200 and ulist, users
    print(f"OK users_count={len(ulist)} names={[u.get('name') for u in ulist]}")
except Exception as e:
    failures.append(f"users: {e}")

try:
    code, nodes = req("GET", "/api/v1/node")
    nlist = nodes.get("nodes") or []
    assert code == 200
    print(f"OK nodes_count={len(nlist)}")
except Exception as e:
    failures.append(f"nodes: {e}")

try:
    code, keys = req("GET", "/api/v1/preauthkey")
    klist = keys.get("preAuthKeys") or keys.get("preauthkeys") or []
    assert code == 200
    print(f"OK preauth_keys_count={len(klist)}")
except Exception as e:
    failures.append(f"preauth list: {e}")

try:
    code, users = req("GET", "/api/v1/user")
    ulist = users.get("users") or []
    user_id = int(ulist[0]["id"])
    exp = (datetime.now(timezone.utc) + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    code, created = req(
        "POST",
        "/api/v1/preauthkey",
        {
            "user": user_id,
            "reusable": False,
            "ephemeral": True,
            "expiration": exp,
            "aclTags": [],
        },
    )
    pak = created.get("preAuthKey") or created
    assert code == 200 and pak.get("key"), created
    print(f"OK preauth_create id={pak.get('id')} key_prefix={pak.get('key','')[:12]}…")
except Exception as e:
    failures.append(f"preauth create: {e}")

if failures:
    print("FAILED:", *failures, sep="\n  ", file=sys.stderr)
    sys.exit(1)
print("Headscale REST smoke: PASS")
PY
