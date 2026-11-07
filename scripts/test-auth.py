#!/usr/bin/env python3
"""Run native SDK regressions on a dedicated disposable simulator. Prints verdicts to stdout."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--udid', help='Use an already reserved test simulator; never delete it')
parser.add_argument('--derived-data', type=Path, help='Reuse an Xcode incremental build directory')
parser.add_argument('--keep-simulator', action='store_true', help='Keep a newly created test simulator for follow-up checks')
parser.add_argument('--only-testing', action='append', default=[], help='XCTest target/class/method selector; may be repeated')
args = parser.parse_args()
output = Path(tempfile.mkdtemp(prefix='webasyst-auth-tests-'))
device = args.udid
created = False

def command(argv, name, capture=False, log=None):
    if log:
        with log.open('w') as stream:
            result = subprocess.run(argv, stdout=stream, stderr=subprocess.STDOUT, timeout=900)
        lines = log.read_text(errors='replace').splitlines()
        for line in lines:
            if re.search(r'^error:|:\d+(?::\d+)?: error:|Test Case .* failed|Executed \d+|\*\* TEST|Test Suite .* (passed|failed)', line, re.I):
                print(line, flush=True)
    else:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=180)
        if result.returncode:
            print((result.stdout + result.stderr)[-4000:], flush=True)
    print(name + ': ' + ('PASS' if result.returncode == 0 else 'FAIL') + ' exit=' + str(result.returncode), flush=True)
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, argv)
    return result.stdout if capture else None

try:
    if not device:
        runtimes = json.loads(command(['xcrun', 'simctl', 'list', 'runtimes', '-j'], 'RUNTIMES', True))['runtimes']
        choices = [r for r in runtimes if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
        if not choices:
            raise RuntimeError('No available iOS runtime')
        runtime = max(choices, key=lambda r: tuple(map(int, r['version'].split('.'))))
        types = json.loads(command(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], 'DEVICE_TYPES', True))['devicetypes']
        phones = [d for d in types if re.match(r'iPhone \d+ Pro$', d['name'])]
        phone = max(phones, key=lambda d: int(re.search(r'\d+', d['name']).group()))
        device = command(['xcrun', 'simctl', 'create', 'WebasystAuth-' + uuid.uuid4().hex[:8], phone['identifier'], runtime['identifier']], 'CREATE_TEST_SIMULATOR', True).strip()
        created = True
        print('TEST_DEVICE: ' + device + ' / ' + phone['name'] + ' / ' + runtime['name'], flush=True)
        command(['xcrun', 'simctl', 'boot', device], 'BOOT')
    command(['xcrun', 'simctl', 'bootstatus', device, '-b'], 'BOOT_READY')
    # Xcode 27 SDK no longer accepts deployment targets below iOS 15. This override affects
    # the verification build only; the distributed SDK retains its iOS 13 deployment target.
    command(['xcodebuild', '-project', str(root / 'Webasyst.xcodeproj'), '-scheme', 'WebasystAuthTests',
             '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + device,
             '-derivedDataPath', str(args.derived_data or output / 'DerivedData'), '-resultBundlePath', str(output / 'Tests.xcresult'),
             '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-',
             'IPHONEOS_DEPLOYMENT_TARGET=15.0', 'ONLY_ACTIVE_ARCH=YES',
             *['-only-testing:' + selector for selector in args.only_testing], 'test'],
            'AUTH_REGRESSION_TESTS', log=output / 'test.log')
    print('FINAL VERDICT: PASS — native Webasyst auth regressions', flush=True)
except (subprocess.SubprocessError, RuntimeError, OSError, ValueError) as error:
    print('FINAL VERDICT: FAIL — ' + str(error), flush=True)
    sys.exit(1)
finally:
    if created and not args.keep_simulator:
        for action in ['shutdown', 'delete']:
            result = subprocess.run(['xcrun', 'simctl', action, device], capture_output=True, text=True)
            print('CLEANUP_' + action.upper() + ': ' + ('PASS' if result.returncode == 0 else 'FAIL'), flush=True)
