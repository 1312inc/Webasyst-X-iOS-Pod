#!/usr/bin/env python3
"""Build the real iOS/watchOS SDK targets and print final verdicts to stdout."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--platform', choices=['ios', 'watchos', 'all'], default='all')
parser.add_argument('--derived-data', type=Path)
parser.add_argument('--minimum-os', action='store_true', help='Build the unchanged minimum OS versions from the project; requires a compatible Xcode SDK')
args = parser.parse_args()
output = args.derived_data or Path(tempfile.mkdtemp(prefix='webasyst-sdk-check-'))
platforms = ['ios', 'watchos'] if args.platform == 'all' else [args.platform]
for platform in platforms:
    scheme, sdk, destination, deployment = (
        ('Webasyst', 'iphonesimulator', 'iOS Simulator', 'IPHONEOS_DEPLOYMENT_TARGET=15.0') if platform == 'ios' else
        ('Webasyst-watchOS', 'watchsimulator', 'watchOS Simulator', 'WATCHOS_DEPLOYMENT_TARGET=9.0'))
    path = output / platform
    path.mkdir(parents=True, exist_ok=True)
    log = path / 'build.log'
    command = ['xcodebuild', '-project', str(root / 'Webasyst.xcodeproj'),
               '-configuration', 'Debug', '-sdk', sdk, 'CODE_SIGNING_ALLOWED=NO']
    if args.minimum_os:
        # Build the framework target without requiring a matching simulator runtime.
        command += ['-target', scheme, 'SYMROOT=' + str(path / 'Products'), 'OBJROOT=' + str(path / 'Intermediates')]
    else:
        command += ['-scheme', scheme, '-destination', 'generic/platform=' + destination,
                    '-derivedDataPath', str(path / 'DerivedData')]
        command.append(deployment)
    command.append('build')
    with log.open('w') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    for line in log.read_text(errors='replace').splitlines():
        if 'error:' in line or '** BUILD' in line:
            print(line, flush=True)
    print('BUILD_' + platform.upper() + ': ' + ('PASS' if result.returncode == 0 else 'FAIL') +
          ' exit=' + str(result.returncode), flush=True)
    if result.returncode:
        sys.exit(result.returncode)
print('FINAL VERDICT: PASS — requested SDK targets built', flush=True)
