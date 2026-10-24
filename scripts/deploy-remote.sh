#!/usr/bin/env bash
# Runs ON Duo Internal as duo-deploy. Duo Deploy's deploy job streams this script over
# ssh (`bash -s`) after uploading a git bundle of the commit to deploy.
#
# Needs: APP_SHA (full commit sha) and the bundle at /tmp/duo-internal-smoke-<short sha>.bundle.
# Idempotent: re-running for the same sha rebuilds and restarts the same version.
set -euo pipefail

APP=duo-internal-smoke
DIR=/srv/apps/$APP
PORT=8100
SHA="${APP_SHA:?APP_SHA is required}"
SHORT="${SHA:0:7}"
BUNDLE="/tmp/$APP-$SHORT.bundle"

[ -f "$BUNDLE" ] || { echo "bundle $BUNDLE missing" >&2; exit 1; }
if [ ! -d "$DIR/.git" ]; then
  echo "==> first deploy: cloning into $DIR"
  git clone -q --no-checkout "$BUNDLE" "$DIR"
fi

cd "$DIR"
echo "==> fetching $SHORT"
git fetch -q "$BUNDLE" HEAD
git -c advice.detachedHead=false checkout -q --detach "$SHA"
rm -f "$BUNDLE"

echo "==> building and starting"
docker compose up -d --build --remove-orphans

echo "==> health check"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null; then
    echo "$APP $SHORT live: $(git log -1 --format=%s)"
    exit 0
  fi
  sleep 1
done
echo "$APP did not become healthy" >&2
docker compose logs --tail 50
exit 1
