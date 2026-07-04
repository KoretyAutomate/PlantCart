#!/usr/bin/env bash
# Turnkey Fly.io deploy for PlantCart. Run AFTER `flyctl auth login`.
#
#   ./deploy-fly.sh <unique-app-name>
#
# Idempotent-ish: re-running redeploys. It creates the app + a persistent volume,
# sets a strong JWT secret (generated here, never committed), and deploys via
# Fly's remote builder (so this aarch64 box doesn't need to build the image).
set -euo pipefail

APP="${1:-}"
REGION="${FLY_REGION:-nrt}"   # Tokyo
if [[ -z "$APP" ]]; then
  echo "usage: ./deploy-fly.sh <unique-app-name>   (e.g. plantcart-arai)" >&2
  exit 1
fi

export PATH="$HOME/.fly/bin:$PATH"
command -v flyctl >/dev/null || { echo "flyctl not found; run the fly.io install first" >&2; exit 1; }
flyctl auth whoami >/dev/null 2>&1 || { echo "Not logged in. Run: flyctl auth login" >&2; exit 1; }

echo "==> Ensuring app '$APP' exists"
flyctl apps create "$APP" 2>/dev/null || echo "   (app already exists — reusing)"

echo "==> Ensuring persistent volume 'plantcart_data' in $REGION"
if ! flyctl volumes list -a "$APP" 2>/dev/null | grep -q plantcart_data; then
  flyctl volumes create plantcart_data --size 1 --region "$REGION" -a "$APP" --yes
else
  echo "   (volume exists — reusing)"
fi

echo "==> Setting PLANTCART_SECRET (generated, not stored anywhere else)"
SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
flyctl secrets set "PLANTCART_SECRET=$SECRET" -a "$APP" >/dev/null
echo "   secret set."

echo "==> Deploying (remote builder)"
flyctl deploy -a "$APP" --remote-only --ha=false --yes

URL="https://$APP.fly.dev"
echo
echo "==> Deployed. Verifying /health ..."
sleep 5
curl -fsS "$URL/health" && echo
echo
echo "PlantCart is live at:  $URL"
echo "Open it, create an account, and share the invite code with your wife."
echo
echo "To enable recipes / plant enrichment later:"
echo "  1) flyctl secrets set ANTHROPIC_API_KEY=sk-ant-... -a $APP"
echo "  2) set PLANTCART_LLM_PROVIDER = \"anthropic\" in fly.toml, then: ./deploy-fly.sh $APP"
