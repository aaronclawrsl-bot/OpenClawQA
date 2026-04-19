#!/usr/bin/env bash
set -euo pipefail

# Deploy OpenClawQA to Taylor's Mac and build
MAC_HOST="taylorolsen-vogt@100.125.133.123"
REMOTE_DIR="~/repos/OpenClawQA"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

echo "=== OpenClawQA Deploy & Build ==="
echo "Source: $PROJECT_ROOT"
echo "Target: $MAC_HOST:$REMOTE_DIR"
echo ""

# Step 1: Sync project to Mac
echo "📦 Syncing project to Mac..."
ssh $SSH_OPTS "$MAC_HOST" "mkdir -p $REMOTE_DIR"
rsync -avz --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude 'DerivedData/' \
  --exclude '*.xcodeproj/' \
  --exclude '.DS_Store' \
  "$PROJECT_ROOT/" "$MAC_HOST:$REMOTE_DIR/"

echo ""

# Step 2: Generate Xcode project on Mac
echo "🔧 Generating Xcode project..."
ssh $SSH_OPTS "$MAC_HOST" "cd $REMOTE_DIR && ruby generate-xcodeproj.rb"

echo ""

# Step 3: Build
echo "🏗️  Building OpenClawQA..."
ssh $SSH_OPTS "$MAC_HOST" "cd $REMOTE_DIR && xcodebuild \
  -project OpenClawQA.xcodeproj \
  -scheme OpenClawQA \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -30"

echo ""
echo "✅ Build complete!"
echo ""

# Step 4: Show build artifact
ssh $SSH_OPTS "$MAC_HOST" "ls -la $REMOTE_DIR/build/DerivedData/Build/Products/Debug/OpenClawQA.app/ 2>/dev/null || echo '(check build output above for errors)'"
