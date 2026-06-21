#!/usr/bin/env bash
# Signs the polyptych Firefox extension with Mozilla's API.
#
# Prerequisites:
#   1. Create API credentials at https://addons.mozilla.org/en-US/developers/addon/api/key/
#   2. Save to ~/.config/polyptych/.env:
#        AMO_JWT_ISSUER="user:12345678"
#        AMO_JWT_SECRET="..."
#
# Then run this script from the extension/firefox/ directory.

set -euo pipefail

cd "$(dirname "$0")"

ENV_FILE="${HOME}/.config/polyptych/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

if [ -z "${AMO_JWT_ISSUER:-}" ] || [ -z "${AMO_JWT_SECRET:-}" ]; then
  echo "Error: AMO_JWT_ISSUER and AMO_JWT_SECRET must be set."
  echo ""
  echo "  Get your API credentials at:"
  echo "    https://addons.mozilla.org/en-US/developers/addon/api/key/"
  echo ""
  echo "  Then run:"
  echo "    export AMO_JWT_ISSUER=\"user:12345678\""
  echo "    export AMO_JWT_SECRET=\"...\""
  echo "    ./sign.sh"
  exit 1
fi

echo "Signing extension with Mozilla API..."
nix run nixpkgs#web-ext -- sign \
  --api-key="$AMO_JWT_ISSUER" \
  --api-secret="$AMO_JWT_SECRET" \
  --channel=unlisted \
  --source-dir="."

echo "Done! Signed .xpi in web-ext-artifacts/"
echo "Install by opening about:addons → gear icon → Install Add-on From File…"
