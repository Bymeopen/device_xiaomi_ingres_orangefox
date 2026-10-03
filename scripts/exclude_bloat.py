#!/usr/bin/env python3
import sys

manifest_file = sys.argv[1] if len(sys.argv) > 1 else 'remove-minimal.xml'

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
</manifest>
"""

try:
    with open(manifest_file, 'r') as f:
        content = f.read()

    if 'kernel/prebuilts/5.15/arm64' not in content:
        content = content.replace('</manifest>', extra_projects.strip() + '\n')
        with open(manifest_file, 'w') as f:
            f.write(content)
        print(f"-- Successfully appended {manifest_file} with heavy bloat exclusions.")
    else:
        print(f"-- {manifest_file} already has exclusions.")
except Exception as e:
    print("Error updating remove-minimal.xml:", e)
