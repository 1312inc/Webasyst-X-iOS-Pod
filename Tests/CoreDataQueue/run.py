#!/usr/bin/env python3
"""Native regression using a real, testable Webasyst simulator framework.

All runtime files and database fixtures stay outside the repository. Use seed
with the old framework, background --expect-violation to prove the regression,
then regression with the fixed framework and the same artifacts directory.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--udid", required=True)
parser.add_argument("--framework", type=Path, required=True)
parser.add_argument("--artifacts", type=Path, required=True)
parser.add_argument("--scenario", choices=["seed", "background", "regression"], required=True)
parser.add_argument("--expect-violation", action="store_true")
args = parser.parse_args()
root = args.artifacts.resolve()
root.mkdir(parents=True, exist_ok=True)
app = root / "WebasystQueueTests.app"
bundle = "com.webasyst.coredataqueuetests"
executable = "WebasystQueueTests"
fixture_folder = "WebasystCoreDataQueueRegression"
backup = root / "legacy-store"


def command(argv, *, check=True, timeout=180):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        # Build/runtime inputs here contain only task paths and fixture values.
        print(result.stdout[-1500:] + result.stderr[-1500:], flush=True)
        raise RuntimeError("Command failed: " + argv[0])
    return result


def activate_if_needed(log):
    if "QUEUE_TEST_PID" in log.read_text(errors="replace"):
        return
    binary = shutil.which("sim-use") or str(Path.home() / ".local/bin/sim-use")
    ui = command([binary, "describe-ui", "--device", args.udid], check=False, timeout=90)
    if "SpringBoard" not in ui.stdout:
        return
    match = re.search(r'Button\s+"Queue Tests"[^\n]*\((\d+),(\d+)\s+(\d+)x(\d+)\)', ui.stdout)
    if match:
        x, y, width, height = map(int, match.groups())
        command([binary, "tap", "--device", args.udid, "--point", f"{x + width // 2},{y + height // 2}"], timeout=90)


try:
    (app / "Frameworks").mkdir(parents=True, exist_ok=True)
    embedded = app / "Frameworks/Webasyst.framework"
    if embedded.exists():
        shutil.rmtree(embedded)
    shutil.copytree(args.framework.resolve(), embedded)
    binary_match = hashlib.sha256((embedded / "Webasyst").read_bytes()).digest() == hashlib.sha256((args.framework / "Webasyst").read_bytes()).digest()
    if not binary_match:
        raise RuntimeError("Framework binary mismatch")
    info = {
        "CFBundleIdentifier": bundle, "CFBundleExecutable": executable,
        "CFBundleName": "Queue Tests", "CFBundleDisplayName": "Queue Tests",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1",
        "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1, 2], "UILaunchScreen": {},
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
                "UISceneConfigurationName": "Default", "UISceneDelegateClassName": executable + ".QueueTestScene"}]}}
    }
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    sdk = command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).stdout.strip()
    source = Path(__file__).with_name("Runner.swift")
    command(["xcrun", "swiftc", "-parse-as-library", "-module-name", executable, "-swift-version", "5", "-sdk", sdk,
        "-target", "arm64-apple-ios15.0-simulator", "-module-cache-path", str(root / "module-cache"),
        "-F", str(app / "Frameworks"), "-framework", "Webasyst", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
        str(source), "-o", str(app / executable)])
    print("QUEUE_TEST_BUILD: PASS", flush=True)
    # This unique fixture app is owned exclusively by this test.
    command(["xcrun", "simctl", "uninstall", args.udid, bundle], check=False)
    command(["xcrun", "simctl", "install", args.udid, str(app)])
    container = Path(command(["xcrun", "simctl", "get_app_container", args.udid, bundle, "data"]).stdout.strip())
    store = container / "Library/Application Support" / fixture_folder
    if args.scenario == "regression":
        if not backup.exists():
            raise RuntimeError("Run seed with the old framework before regression")
        store.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(backup, store, dirs_exist_ok=True)
    verdict = container / "Documents/verdict.txt"
    log = root / (args.scenario + ("-before" if args.expect_violation else "") + ".log")
    with log.open("w") as stream:
        started = time.time()
        proc = subprocess.Popen(["xcrun", "simctl", "launch", "--terminate-running-process", "--console", args.udid,
            bundle, "-com.apple.CoreData.ConcurrencyDebug", "1", args.scenario], stdout=stream, stderr=subprocess.STDOUT, text=True)
        time.sleep(1)
        activate_if_needed(log)
        for _ in range(1200):
            if proc.poll() is not None:
                break
            if verdict.exists() and verdict.read_text().startswith(("PASS", "FAIL")):
                break
            time.sleep(0.1)
        text = log.read_text(errors="replace")
        state = verdict.read_text() if verdict.exists() else "NO_VERDICT"
        pid_match = re.search(r"QUEUE_TEST_PID (\d+)", text)
        pid = int(pid_match.group(1)) if pid_match else None
        debug_enabled = "multi-threading assertions enabled" in text
        report_name = None
        if args.expect_violation:
            for _ in range(200):
                for path in Path.home().joinpath("Library/Logs/DiagnosticReports").glob(executable + "-*.ips"):
                    if path.stat().st_mtime < started:
                        continue
                    raw = path.read_text(errors="replace")
                    try:
                        # macOS may append a human-readable System Profile after the JSON.
                        report, _ = json.JSONDecoder().raw_decode(raw[raw.find("\n{") + 1:])
                        thread = report["threads"][report["faultingThread"]]
                    except (ValueError, KeyError, TypeError):
                        continue
                    symbols = [frame.get("symbol", "") for frame in thread.get("frames", [])]
                    if report.get("pid") == pid and any("_PFAssertSafeMultiThreadedAccess_impl" in item for item in symbols) and any("WebasystDataModel.getInstallList" in item for item in symbols):
                        report_name = path.name
                        break
                if report_name:
                    break
                time.sleep(0.1)
            passed = debug_enabled and report_name is not None
        else:
            passed = debug_enabled and state.startswith("PASS")
        command(["xcrun", "simctl", "terminate", args.udid, bundle], check=False)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.terminate()
    if args.scenario == "seed" and passed:
        if backup.exists():
            shutil.rmtree(backup)
        shutil.copytree(store, backup)
    result = {"scenario": args.scenario, "pass": passed, "state": state, "pid": pid,
        "debugEnabled": debug_enabled, "matchingReport": report_name, "frameworkBinaryMatch": binary_match}
    (root / (args.scenario + ("-before" if args.expect_violation else "") + "-verdict.json")).write_text(json.dumps(result, indent=2))
    print("COREDATA_QUEUE_" + args.scenario.upper() + ": " + ("PASS" if passed else "FAIL") + " " + json.dumps(result), flush=True)
    raise SystemExit(0 if passed else 1)
except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
    print("COREDATA_QUEUE_TEST: FAIL " + str(error), flush=True)
    raise SystemExit(1)
