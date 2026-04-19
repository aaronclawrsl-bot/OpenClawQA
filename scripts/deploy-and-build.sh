#!/usr/bin/env bash
set -euo pipefail

# Build OpenClawQA locally on this Mac
# Usage: ./scripts/deploy-and-build.sh [--harness] [--clean]
#   --harness  Also build the OCQAHarness XCUITest bundle
#   --clean    Clean derived data before building

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_HARNESS=0
DO_CLEAN=0

for arg in "$@"; do
  case "$arg" in
    --harness) BUILD_HARNESS=1 ;;
    --clean) DO_CLEAN=1 ;;
  esac
done

echo "=== OpenClawQA Local Build ==="
echo "Project: $PROJECT_ROOT"
echo ""

if [[ $DO_CLEAN -eq 1 ]]; then
  echo "Cleaning derived data..."
  rm -rf "$PROJECT_ROOT/build/DerivedData"
  rm -rf /tmp/openclaw-qa-harness-derived
  echo ""
fi

# Step 1: Generate Xcode project if needed
if [[ ! -f "$PROJECT_ROOT/OpenClawQA.xcodeproj/project.pbxproj" ]] || \
   [[ "$PROJECT_ROOT/generate-xcodeproj.rb" -nt "$PROJECT_ROOT/OpenClawQA.xcodeproj/project.pbxproj" ]]; then
  echo "Generating Xcode project..."
  cd "$PROJECT_ROOT" && ruby generate-xcodeproj.rb
  echo ""
fi

# Step 2: Build main app
echo "Building OpenClawQA..."
xcodebuild \
  -project "$PROJECT_ROOT/OpenClawQA.xcodeproj" \
  -scheme OpenClawQA \
  -configuration Debug \
  -derivedDataPath "$PROJECT_ROOT/build/DerivedData" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -20

echo ""

# Step 3: Build harness if requested
if [[ $BUILD_HARNESS -eq 1 ]]; then
  echo "Building OCQAHarness..."

  # Generate harness xcodeproj if needed
  if [[ ! -f "$PROJECT_ROOT/Harness/OCQAHarness.xcodeproj/project.pbxproj" ]] || \
     [[ "$PROJECT_ROOT/Harness/generate-harness-xcodeproj.rb" -nt "$PROJECT_ROOT/Harness/OCQAHarness.xcodeproj/project.pbxproj" ]]; then
    cd "$PROJECT_ROOT/Harness" && ruby generate-harness-xcodeproj.rb
  fi

  # Detect available simulator
  SIM_NAME=$(xcrun simctl list devices available | grep -E 'iPhone.*(Booted|Shutdown)' | head -1 | sed 's/ (.*//' | xargs)
  SIM_NAME=${SIM_NAME:-"iPhone 16 Pro"}
  echo "  Target simulator: $SIM_NAME"

  xcodebuild build-for-testing \
    -project "$PROJECT_ROOT/Harness/OCQAHarness.xcodeproj" \
    -scheme OCQAHarnessUITests \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -derivedDataPath "/tmp/openclaw-qa-harness-derived" \
    2>&1 | tail -20

  echo ""
  echo "Harness built. Quick capture:"
  echo "  ./scripts/quick-capture.sh explore com.elitepro.resilife --actions 25"
  echo "  ./scripts/quick-capture.sh screenshot"
  echo "  ./scripts/quick-capture.sh tree com.elitepro.resilife"
fi

echo ""
APP_PATH="$PROJECT_ROOT/build/DerivedData/Build/Products/Debug/OpenClawQA.app"
if [[ -d "$APP_PATH" ]]; then
  echo "Build artifact: $APP_PATH"
  echo "Run: open $APP_PATH"
else
  echo "(check build output above for errors)"
fi
