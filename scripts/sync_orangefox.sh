#!/usr/bin/env bash
# ==============================================================================
# Script: sync_orangefox.sh
# Purpose: Sync OrangeFox minimal tree (fox_14.1) with disk space optimizations
# ==============================================================================
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$HOME}"
TARGET_DIR="${1:-$WORKSPACE/fox_14.1}"
SYNC_DIR="$WORKSPACE/OrangeFox_sync"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EXCLUDE_PY="$SCRIPT_DIR/exclude_bloat.py"

echo "=== Syncing OrangeFox 14.1 to: $TARGET_DIR ==="
echo "Using bloat exclusion script: $EXCLUDE_PY"

mkdir -p "$SYNC_DIR"
if [ ! -d "$SYNC_DIR/.git" ]; then
    git clone https://github.com/Just-TWRP/OrangeFox_sync.git "$SYNC_DIR"
fi

cd "$SYNC_DIR"

# 1. Patch DEVICE_BRANCH to android-14.1 for qcom common repo
sed -i 's/DEVICE_BRANCH="android-14"/DEVICE_BRANCH="android-14.1"/g' orangefox_sync.sh

# 2. Add Darwin/macOS omission to repo init
sed -i 's/repo init --depth=1 -u $MIN_MANIFEST -b $TWRP_BRANCH/repo init --depth=1 -u $MIN_MANIFEST -b $TWRP_BRANCH -g default,-darwin,-notdefault/g' orangefox_sync.sh

# 3. Optimize repo sync with shallow branch filter
sed -i 's/repo sync -j25/repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags --prune/g' orangefox_sync.sh

# 4. Use shallow clone (--depth=1) for all sub-repos
sed -i 's/git clone $URL -b $BRANCH recovery/git clone --depth=1 $URL -b $BRANCH recovery/g' orangefox_sync.sh
sed -i 's/git clone https:\/\/github.com\/TeamWin\/android_device_qcom_common -b $DEVICE_BRANCH device\/qcom\/common/git clone --depth=1 https:\/\/github.com\/TeamWin\/android_device_qcom_common -b $DEVICE_BRANCH device\/qcom\/common/g' orangefox_sync.sh
sed -i 's/git clone https:\/\/github.com\/TeamWin\/android_device_qcom_twrp-common -b $DEVICE_BRANCH device\/qcom\/twrp-common/git clone --depth=1 https:\/\/github.com\/TeamWin\/android_device_qcom_twrp-common -b $DEVICE_BRANCH device\/qcom\/twrp-common/g' orangefox_sync.sh

# 5. Inject exclude_bloat.py call right before repo sync
python3 - << 'PYEOF'
import os
exclude_py = os.environ.get('EXCLUDE_PY', '')

with open('orangefox_sync.sh', 'r') as f:
    code = f.read()

target = 'echo "-- Syncing the $TWRP_BRANCH minimal manifest repo ...";'
injection = f'  python3 "{exclude_py}" "$MANIFEST_DIR/.repo/manifests/remove-minimal.xml"\n  ' + target

if target in code and 'exclude_bloat.py' not in code:
    code = code.replace(target, injection, 1)
    with open('orangefox_sync.sh', 'w') as f:
        f.write(code)
    print("Injected exclude_bloat call into orangefox_sync.sh successfully.")
PYEOF

bash -n orangefox_sync.sh

echo "Running optimized OrangeFox sync script..."
./orangefox_sync.sh --branch 14.1 --path "$TARGET_DIR"

echo "Reclaiming disk space by removing .repo metadata directory..."
rm -rf "$TARGET_DIR/.repo"

echo "=== Disk Space After Sync & Cleanup ==="
df -h
