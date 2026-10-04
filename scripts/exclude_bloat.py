#!/usr/bin/env python3
# ==============================================================================
# Script: exclude_bloat.py
# Purpose: Prunes heavy unused AOSP/TWRP projects from manifests before repo sync
# ==============================================================================
import os
import sys

manifests_dir = sys.argv[1] if len(sys.argv) > 1 else '.repo/manifests'

# 1. Update remove-minimal.xml to exclude heavy unneeded prebuilts & kernels
rem_file = os.path.join(manifests_dir, 'remove-minimal.xml')
extra_projects = """    <remove-project path="kernel/prebuilts/5.15/arm64" />
    <remove-project path="kernel/prebuilts/5.15/x86_64" />
    <remove-project path="kernel/prebuilts/6.6/arm64" />
    <remove-project path="kernel/prebuilts/6.6/x86_64" />
    <remove-project path="kernel/prebuilts/common-modules/virtual-device/5.15/arm64" />
    <remove-project path="kernel/prebuilts/common-modules/virtual-device/5.15/x86-64" />
    <remove-project path="kernel/prebuilts/common-modules/virtual-device/6.6/arm64" />
    <remove-project path="kernel/prebuilts/common-modules/virtual-device/6.6/x86-64" />
    <remove-project path="prebuilts/jdk/jdk11" />
    <remove-project path="prebuilts/jdk/jdk21" />
    <remove-project path="prebuilts/jdk/jdk8" />
    <remove-project path="prebuilts/vndk/v29" />
    <remove-project path="prebuilts/vndk/v30" />
    <remove-project path="prebuilts/vndk/v31" />
    <remove-project path="prebuilts/vndk/v32" />
    <remove-project path="prebuilts/vndk/v33" />
    <remove-project path="tools/tradefederation/core" />
    <remove-project path="tools/tradefederation/contrib" />
    <remove-project path="prebuilts/abi-dumps/ndk" />
    <remove-project path="prebuilts/abi-dumps/platform" />
    <remove-project path="prebuilts/abi-dumps/vndk" />
    <remove-project path="prebuilts/bazel/common" />
    <remove-project path="prebuilts/bazel/darwin-x86_64" />
    <remove-project path="prebuilts/bazel/linux-x86_64" />
</manifest>
"""

try:
    if os.path.exists(rem_file):
        with open(rem_file, 'r') as f:
            c = f.read()
        if 'kernel/prebuilts/5.15/arm64' not in c:
            c = c.replace('</manifest>', extra_projects.strip() + '\n')
            with open(rem_file, 'w') as f:
                f.write(c)
            print(f"-- Successfully updated {rem_file} with heavy bloat exclusions.")
        else:
            print(f"-- {rem_file} already has exclusions.")
except Exception as e:
    print("Error updating remove-minimal.xml:", e)

# 2. In twrp-default.xml, remove android_cts which takes several GB
twrp_def_file = os.path.join(manifests_dir, 'twrp-default.xml')
try:
    if os.path.exists(twrp_def_file):
        with open(twrp_def_file, 'r') as f:
            lines = f.readlines()
        filtered = [l for l in lines if 'name="android_cts"' not in l]
        with open(twrp_def_file, 'w') as f:
            f.writelines(filtered)
        print(f"-- Removed android_cts from {twrp_def_file}")
except Exception as e:
    print("Error updating twrp-default.xml:", e)

