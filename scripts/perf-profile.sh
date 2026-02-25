#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/build/perf-derived-data}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/perf}"
SCHEME="${SCHEME:-ClipboardRefiner}"
CONFIGURATION="${CONFIGURATION:-Release}"
DURATION_SECONDS="${1:-90}"

mkdir -p "$OUTPUT_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
log_file="$OUTPUT_DIR/perf-$timestamp.jsonl"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$ROOT_DIR/ClipboardRefiner.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build >/tmp/clipboardrefiner-perf-build.log

app_binary="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/ClipboardRefiner.app/Contents/MacOS/ClipboardRefiner"
if [[ ! -x "$app_binary" ]]; then
  echo "App binary not found at $app_binary" >&2
  exit 1
fi

echo "Launching with CLIPBOARD_REFINER_PERF=1 for ${DURATION_SECONDS}s..."
CLIPBOARD_REFINER_PERF=1 "$app_binary" 2>"$log_file" >/dev/null &
app_pid=$!

sleep "$DURATION_SECONDS" || true
kill "$app_pid" >/dev/null 2>&1 || true
wait "$app_pid" >/dev/null 2>&1 || true

echo "Perf log: $log_file"
echo "Tip: summarize with:"
echo "python3 - <<'PY' '$log_file'"
echo "import json,sys,collections"
echo "path=sys.argv[1]"
echo "timers=collections.defaultdict(list)"
echo "with open(path) as f:"
echo "  for line in f:"
echo "    try: p=json.loads(line)"
echo "    except: continue"
echo "    if p.get('type')=='perf' and p.get('kind')=='timer':"
echo "      timers[p.get('metric','unknown')].append(float(p.get('duration_ms',0)))"
echo "for m,vals in sorted(timers.items()):"
echo "  vals=sorted(vals)"
echo "  p95=vals[max(0,int(len(vals)*0.95)-1)]"
echo "  print(f'{m}: n={len(vals)} avg={sum(vals)/len(vals):.2f}ms p95={p95:.2f}ms max={vals[-1]:.2f}ms')"
echo "PY"
