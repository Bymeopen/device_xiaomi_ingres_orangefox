#!/usr/bin/env bash
# ==============================================================================
# Script: sync_orangefox.sh
# Purpose: Sync OrangeFox minimal tree (fox_14.1) with disk space optimizations
# ==============================================================================
set -euo pipefail

TARGET_DIR="${1:-$HOME/fox_14.1}"
SYNC_DIR="$HOME/OrangeFox_sync"

echo "=== Syncing OrangeFox 14.1 to: $TARGET_DIR ==="

mkdir -p "$SYNC_DIR"
if [ ! -d "$SYNC_DIR/.git" ]; then
    git clone https://github.com/Just-TWRP/OrangeFox_sync.git "$SYNC_DIR"
fi

cd "$SYNC_DIR"

# 1. Patch DEVICE_BRANCH to android-14.1
sed -i 's/DEVICE_BRANCH="android-14"/DEVICE_BRANCH="android-14.1"/g' orangefox_sync.sh

# 2. Add Darwin/macOS omission to repo init
sed -i 's/repo init --depth=1 -u $MIN_MANIFEST -b $TWRP_BRANCH/repo init --depth=1 -u $MIN_MANIFEST -b $TWRP_BRANCH -g default,-darwin,-notdefault/g' orangefox_sync.sh

# 3. Optimize repo sync with shallow branch filter
sed -i 's/repo sync -j25/repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags --prune/g' orangefox_sync.sh

# 4. Use shallow clone (--depth=1) for all sub-repos
sed -i 's/git clone $URL -b $BRANCH recovery/git clone --depth=1 $URL -b $BRANCH recovery/g' orangefox_sync.sh
sed -i 's/git clone https:\/\/github.com\/TeamWin\/android_device_qcom_common -b $DEVICE_BRANCH device\/qcom\/common/git clone --depth=1 https:\/\/github.com\/TeamWin\/android_device_qcom_common -b $DEVICE_BRANCH device\/qcom\/common/g' orangefox_sync.sh
sed -i 's/git clone https:\/\/github.com\/TeamWin\/android_device_qcom_twrp-common -b $DEVICE_BRANCH device\/qcom\/twrp-common/git clone --depth=1 https:\/\/github.com\/TeamWin\/android_device_qcom_twrp-common -b $DEVICE_BRANCH device\/qcom\/twrp-common/g' orangefox_sync.sh

# 5. Inject local_manifests to exclude 75+ heavy unused projects (kernel prebuilts, old JDKs, VNDKs, CTS)
python3 - << 'PYEOF'
with open('orangefox_sync.sh', 'r') as f:
    code = f.read()

target = 'echo "-- Syncing the $TWRP_BRANCH minimal manifest repo ...";'
injection = r'''  mkdir -p "$MANIFEST_DIR/.repo/local_manifests"
  python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$MANIFEST_DIR/.repo/manifests/default.xml')
    removals = []
    patterns = ['cts', 'kernel/prebuilts', 'jdk8', 'jdk9', 'jdk11', 'jdk21', 'darwin', 'emulator', 'qemu', 'vndk/v2', 'vndk/v30', 'vndk/v31', 'vndk/v32', 'vndk/v33', 'tradefederation', 'module_sdk']
    for p in tree.getroot().findall('project'):
        name = p.get('name', '')
        path = p.get('path', '')
        if any(pat in path for pat in patterns):
            removals.append(f'  <remove-project name=\"{name}\" />')
    with open('$MANIFEST_DIR/.repo/local_manifests/remove_bloat.xml', 'w') as f:
        f.write('<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest>\n' + '\n'.join(removals) + '\n</manifest>\n')
    print(f'-- Excluded {len(removals)} unneeded heavy projects from sync.')
except Exception as e:
    print('Warning during bloat exclusion:', e)
"
  ''' + target

if target in code and 'remove_bloat.xml' not in code:
    code = code.replace(target, injection, 1)
    with open('orangefox_sync.sh', 'w') as f:
        f.write(code)
    print("Injected bloat exclusion logic into orangefox_sync.sh")
PYEOF

bash -n orangefox_sync.sh

echo "Running optimized OrangeFox sync script..."
./orangefox_sync.sh --branch 14.1 --path "$TARGET_DIR"

echo "Reclaiming disk space by removing .repo metadata directory..."
rm -rf "$TARGET_DIR/.repo"

echo "=== Disk Space After Sync & Cleanup ==="
df -h /
