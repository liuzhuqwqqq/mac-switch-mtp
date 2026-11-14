#!/usr/bin/env python3
"""Reject bundles that depend on newer macOS binaries or local build paths."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess


def version(value):
    return tuple(int(part) for part in value.split('.')) + (0,) * (3 - len(value.split('.')))


def verify(app, deployment_target):
    app = Path(app).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert version(info['LSMinimumSystemVersion']) == version(deployment_target), 'Info.plist target differs'
    binaries = [app / 'Contents/MacOS/SwitchMTP', app / 'Contents/MacOS/mtp-helper',
                app / 'Contents/Frameworks/libmtp.9.dylib', app / 'Contents/Frameworks/libusb-1.0.0.dylib']
    names = {path.name for path in binaries}
    for path in binaries:
        build = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(path)], text=True)
        targets = re.findall(r'\bminos\s+(\d+(?:\.\d+)+)', build)
        assert targets and all(version(v) <= version(deployment_target) for v in targets), f'{path.name}: newer minimum macOS {targets}'
        libs = subprocess.check_output(['otool', '-L', str(path)], text=True)
        for line in libs.splitlines()[1:]:
            dependency = line.strip().split(' (compatibility version')[0]
            if dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            assert dependency.startswith(('@loader_path/', '@executable_path/', '@rpath/')), f'{path.name}: external dependency {dependency}'
            assert Path(dependency).name in names, f'{path.name}: unbundled dependency {dependency}'
        imports = subprocess.check_output(['xcrun', 'dyld_info', '-imports', str(path)], text=True)
        assert not re.search(r'\b_?pipe2\b', imports), f'{path.name}: macOS 27-only pipe2 import'
        print(f'{path.name}: macOS {targets}, bundled/system dependencies only')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app')
    parser.add_argument('--deployment-target', default='13.0')
    args = parser.parse_args()
    verify(args.app, args.deployment_target)
