#!/usr/bin/env bash
# Builds example/lib/main_browser_probe.dart for the web and runs it in
# headless Chrome. The probe drives the URL routing demo through the real
# browser history (including a page reload) and checks app state, address bar
# and history length after every step.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/example/build/browser_probe"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

cd "$root/example"
flutter build web --no-web-resources-cdn --no-wasm-dry-run \
  -t lib/main_browser_probe.dart -o "$out" --base-href "$out/"

work="$(mktemp -d)"
cleanup() {
  if [[ -n "${pid:-}" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  # Chrome's helpers can still hold files in the profile; the probe's result
  # must not depend on removing them
  rm -rf "$work" 2>/dev/null || true
}
trap cleanup EXIT
"$chrome" --headless=new --no-first-run --no-default-browser-check \
  --allow-file-access-from-files --enable-unsafe-swiftshader \
  --use-angle=swiftshader --enable-logging=stderr --v=0 \
  --user-data-dir="$work/profile" "file://$out/index.html#/orders" \
  2> "$work/console.log" &
pid=$!

for _ in $(seq 1 120); do
  if grep -q 'PROBE DONE\|PROBE ERROR' "$work/console.log"; then break; fi
  sleep 1
done

grep -o '"PROBE[^"]*"' "$work/console.log" | sed 's/^"PROBE //; s/"$//'
grep -q 'PROBE DONE 0 failed' "$work/console.log"
