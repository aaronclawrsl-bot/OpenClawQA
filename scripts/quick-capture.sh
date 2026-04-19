#!/usr/bin/env bash
set -euo pipefail

# quick-capture.sh — Fast local screenshot/video capture from iOS simulator
#
# This runs LOCALLY on the Mac (no SSH). It's the Mac-local equivalent of
# ewag-capture.sh (which runs on the gateway and SSHes into a Mac).
#
# Usage:
#   quick-capture.sh screenshot [--app <bundleId>]   # Screenshot current sim state
#   quick-capture.sh record [--duration <secs>]      # Record sim video
#   quick-capture.sh explore <bundleId> [--actions N] # Run autonomous exploration + capture
#   quick-capture.sh tree <bundleId>                  # Dump accessibility tree
#
# All output goes to ~/repos/OpenClawQA/captures/<timestamp>/

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAPTURE_DIR="$PROJECT_ROOT/captures/$(date +%Y%m%d-%H%M%S)"
HARNESS_PROJECT="$PROJECT_ROOT/Harness/OCQAHarness.xcodeproj"
HARNESS_DERIVED="/tmp/openclaw-qa-harness-derived"
DEFAULT_BUNDLE="com.elitepro.resilife"

get_booted_sim() {
  xcrun simctl list devices booted -j 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
for runtime, devices in d.get('devices', {}).items():
    for dev in devices:
        if dev.get('state') == 'Booted':
            print(dev['udid'])
            sys.exit(0)
" 2>/dev/null
}

get_sim_name() {
  xcrun simctl list devices booted -j 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
for runtime, devices in d.get('devices', {}).items():
    for dev in devices:
        if dev.get('state') == 'Booted':
            print(dev['name'])
            sys.exit(0)
" 2>/dev/null
}

ensure_harness_built() {
  local sim_name="${1:-iPhone 16 Pro}"
  local xctestrun=$(find "$HARNESS_DERIVED/Build/Products" -name "*.xctestrun" 2>/dev/null | head -1)
  if [[ -n "$xctestrun" ]]; then
    echo "Harness already built: $xctestrun" >&2
    return 0
  fi
  echo "Building harness..." >&2
  xcodebuild build-for-testing \
    -project "$HARNESS_PROJECT" \
    -scheme OCQAHarnessUITests \
    -destination "platform=iOS Simulator,name=$sim_name" \
    -derivedDataPath "$HARNESS_DERIVED" \
    2>&1 | tail -5 >&2
}

run_harness_test() {
  local test_method="$1"
  local sim_name="${2:-iPhone 16 Pro}"
  local bundle_id="${3:-$DEFAULT_BUNDLE}"
  local max_actions="${4:-25}"
  local timeout_secs="${5:-300}"

  cat > /tmp/ocqa-run-config.json << CONF
{
  "OCQA_BUNDLE_ID": "$bundle_id",
  "OCQA_MAX_ACTIONS": "$max_actions",
  "OCQA_TIMEOUT_SECONDS": "$timeout_secs",
  "OCQA_TEST_EMAIL": "${OCQA_TEST_EMAIL:-demo@eliteproai.com}",
  "OCQA_TEST_PASSWORD": "${OCQA_TEST_PASSWORD:-Demo1234!}"
}
CONF

  local xctestrun=$(find "$HARNESS_DERIVED/Build/Products" -name "*.xctestrun" 2>/dev/null | head -1)
  if [[ -z "$xctestrun" ]]; then
    echo "ERROR: No xctestrun found. Run: ./scripts/deploy-and-build.sh --harness" >&2
    return 1
  fi

  xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "platform=iOS Simulator,name=$sim_name" \
    -only-testing:"OCQAHarnessUITests/ExplorerTests/$test_method" \
    -resultBundlePath "$CAPTURE_DIR/result.xcresult" \
    2>&1
}

# --- Main ---
MODE="${1:-screenshot}"
shift || true

APP_BUNDLE="$DEFAULT_BUNDLE"
DURATION=30
MAX_ACTIONS=25

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_BUNDLE="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --actions) MAX_ACTIONS="$2"; shift 2 ;;
    *) APP_BUNDLE="$1"; shift ;;
  esac
done

mkdir -p "$CAPTURE_DIR"
UDID=$(get_booted_sim)
SIM_NAME=$(get_sim_name)

if [[ -z "$UDID" ]]; then
  echo "ERROR: No booted simulator found. Boot one first:"
  echo "  xcrun simctl boot 'iPhone 16 Pro'"
  exit 1
fi
echo "Simulator: $SIM_NAME ($UDID)"
echo "Output: $CAPTURE_DIR"
echo ""

case "$MODE" in
  screenshot)
    echo "Taking screenshot..."
    xcrun simctl io "$UDID" screenshot "$CAPTURE_DIR/screenshot.png"
    echo "Saved: $CAPTURE_DIR/screenshot.png"
    ls -lh "$CAPTURE_DIR/screenshot.png"
    ;;

  record)
    echo "Recording for ${DURATION}s... (Ctrl+C to stop early)"
    xcrun simctl io "$UDID" recordVideo --codec=h264 "$CAPTURE_DIR/recording.mov" &
    RECORD_PID=$!
    sleep "$DURATION"
    kill -INT $RECORD_PID 2>/dev/null || true
    wait $RECORD_PID 2>/dev/null || true
    sleep 1

    if [[ -f "$CAPTURE_DIR/recording.mov" ]]; then
      echo "Converting to WebM..."
      ffmpeg -hide_banner -loglevel error -y \
        -i "$CAPTURE_DIR/recording.mov" \
        -c:v libvpx-vp9 -crf 36 -b:v 0 -row-mt 1 -an \
        "$CAPTURE_DIR/recording.webm"
      echo "Saved: $CAPTURE_DIR/recording.webm ($(du -h "$CAPTURE_DIR/recording.webm" | cut -f1))"
      echo "Raw:   $CAPTURE_DIR/recording.mov ($(du -h "$CAPTURE_DIR/recording.mov" | cut -f1))"
    fi
    ;;

  explore)
    echo "Running autonomous exploration ($MAX_ACTIONS actions, app: $APP_BUNDLE)..."
    ensure_harness_built "$SIM_NAME"

    # Start video recording in background
    xcrun simctl io "$UDID" recordVideo --codec=h264 "$CAPTURE_DIR/exploration.mov" &
    RECORD_PID=$!
    sleep 0.5

    # Run exploration
    OUTPUT=$(run_harness_test "testAutonomousExploration" "$SIM_NAME" "$APP_BUNDLE" "$MAX_ACTIONS" "300")

    # Stop recording
    kill -INT $RECORD_PID 2>/dev/null || true
    wait $RECORD_PID 2>/dev/null || true
    sleep 1

    # Parse OCQA_ markers
    echo "$OUTPUT" | grep "^OCQA_" > "$CAPTURE_DIR/ocqa-markers.txt" || true
    echo "$OUTPUT" > "$CAPTURE_DIR/full-output.txt"

    COMPLETE_LINE=$(echo "$OUTPUT" | grep "OCQA_COMPLETE" | tail -1)
    if [[ -n "$COMPLETE_LINE" ]]; then
      echo ""
      echo "Exploration complete: $COMPLETE_LINE"
    fi

    # Extract screenshots from xcresult
    if [[ -d "$CAPTURE_DIR/result.xcresult" ]]; then
      mkdir -p "$CAPTURE_DIR/screenshots"
      xcrun xcresulttool export attachments \
        --path "$CAPTURE_DIR/result.xcresult" \
        --output-path "$CAPTURE_DIR/screenshots" 2>/dev/null || true
      SC_COUNT=$(find "$CAPTURE_DIR/screenshots" -name "*.png" 2>/dev/null | wc -l | xargs)
      echo "Extracted $SC_COUNT screenshots from xcresult"
    fi

    # Convert video
    if [[ -f "$CAPTURE_DIR/exploration.mov" ]]; then
      echo "Converting exploration video to WebM..."
      ffmpeg -hide_banner -loglevel error -y \
        -i "$CAPTURE_DIR/exploration.mov" \
        -c:v libvpx-vp9 -crf 36 -b:v 0 -row-mt 1 -an \
        "$CAPTURE_DIR/exploration.webm"
      echo "Video: $CAPTURE_DIR/exploration.webm ($(du -h "$CAPTURE_DIR/exploration.webm" | cut -f1))"
    fi

    echo ""
    echo "All artifacts in: $CAPTURE_DIR/"
    ls -lh "$CAPTURE_DIR/"
    ;;

  tree)
    echo "Dumping accessibility tree for $APP_BUNDLE..."
    ensure_harness_built "$SIM_NAME"
    OUTPUT=$(run_harness_test "testDumpUITree" "$SIM_NAME" "$APP_BUNDLE" "1" "60")

    echo "$OUTPUT" | sed -n '/OCQA_UITREE_START/,/OCQA_UITREE_END/p' | grep -v "OCQA_UITREE" > "$CAPTURE_DIR/uitree.json" || true
    echo "$OUTPUT" > "$CAPTURE_DIR/full-output.txt"

    if [[ -s "$CAPTURE_DIR/uitree.json" ]]; then
      ELEMENTS=$(python3 -c "import json; d=json.load(open('$CAPTURE_DIR/uitree.json')); print(len(d.get('elements',[])))" 2>/dev/null || echo "?")
      echo "Tree saved: $CAPTURE_DIR/uitree.json ($ELEMENTS elements)"
    else
      echo "WARNING: No tree JSON extracted. Check $CAPTURE_DIR/full-output.txt"
    fi
    ;;

  *)
    echo "Usage: quick-capture.sh <screenshot|record|explore|tree> [options]"
    echo ""
    echo "  screenshot [--app <id>]            Screenshot current simulator state"
    echo "  record [--duration <secs>]         Record simulator video (default 30s)"
    echo "  explore <bundleId> [--actions N]   Autonomous exploration + capture"
    echo "  tree <bundleId>                    Dump accessibility tree JSON"
    exit 1
    ;;
esac
