# Core Data queue regression

The runner links the real Debug Webasyst simulator framework with testability
enabled. It uses a unique test app and a dedicated database folder. It never
reads a customer account or sends network requests. Every command prints its
verdict directly to stdout and exits nonzero on failure.

Build the framework with the repository's `Webasyst` scheme. On Xcode 27 use a
temporary `IPHONEOS_DEPLOYMENT_TARGET=15.0` command-line override because that SDK
no longer builds iOS 13 targets. This does not change the library's minimum OS.

```sh
xcodebuild -project Webasyst.xcodeproj -scheme Webasyst -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$QUEUE_ARTIFACTS/DerivedData" \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES build
```

Set `QUEUE_ARTIFACTS` to a task-owned directory outside the repository and provide
an idle simulator's exact UDID. Use the same artifacts directory for all phases:

1. Build the original SDK and save a copy of its `Webasyst.framework`. Run `seed`
   against that copy to create the existing SQLite/profile fixture. Run
   `background --expect-violation` against the same original framework: the
   expected Core Data assertion must match the launched PID and `getInstallList`.
2. Build the fixed SDK. Run `regression` against it. The runner restores the old
   SQLite fixture into a fresh test-app container and checks preservation, all
   CRUD methods, public SDK reads, concurrent reads/writes, background deinit,
   and updates to the same installation/profile through separate SDK instances.

```sh
python3 Tests/CoreDataQueue/run.py --udid "$QUEUE_SIMULATOR_UDID" \
  --framework "$QUEUE_BASELINE_FRAMEWORK" --artifacts "$QUEUE_ARTIFACTS/native" --scenario seed
python3 Tests/CoreDataQueue/run.py --udid "$QUEUE_SIMULATOR_UDID" \
  --framework "$QUEUE_BASELINE_FRAMEWORK" --artifacts "$QUEUE_ARTIFACTS/native" \
  --scenario background --expect-violation
python3 Tests/CoreDataQueue/run.py --udid "$QUEUE_SIMULATOR_UDID" \
  --framework "$QUEUE_FIXED_FRAMEWORK" --artifacts "$QUEUE_ARTIFACTS/native" --scenario regression
```

Core Data concurrency diagnostics stay enabled for every phase. Tests use actual
framework methods, not copies of persistence implementation. The simulator and
the uniquely named test app must belong to this task; the runner reinstalls only
that test app. Release the simulator and remove the test app when finished.
