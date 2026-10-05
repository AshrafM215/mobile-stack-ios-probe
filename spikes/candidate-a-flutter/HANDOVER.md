# Handover: candidate A (Flutter)

NON-PRODUCTION / SYNTHETIC DATA ONLY.

## 1. What this application is

Candidate A is a wayfinding application for a synthetic set of buildings. The home screen has a search field, a result list, floor buttons for floors 1 to 3 and a map. Other screens show the details and schedule of a destination, a route with text steps from a chosen entrance, a native AR screen or a text fallback, the result of a scanned anchor code (QR), and the state of the installed data ("data and trust"). All data is synthetic and generated under `synthetic-data/`; it describes no real place and the application is not for navigation. The application is written in Dart with Flutter (SDK 3.47.5, pinned in `candidate-a-flutter/g1-toolchain.json`). A local plugin in Kotlin and Swift connects it to a shared native module (Java on Android, Swift on iOS). The interface languages are Arabic (the start language, right to left) and English.

## 2. Layout

Paths are relative to the tree root.

- `candidate-a-flutter/lib/main.dart`: entry point. `main()` loads the two string files, creates `AppState`, runs the widget `G1App`, calls `AppState.boot()` and starts `LabController`.
- `candidate-a-flutter/lib/src/app_state.dart`: `AppState`, the one state object, with the handlers that the screens and the lab hooks share. Also `ScreenKind`, `ScreenEntry` and the interface `MapPort`.
- `candidate-a-flutter/lib/src/ui/screens.dart`: all screens as widgets: `G1App`, `_Root`, `HomeScreen`, `DetailsScreen`, `RouteScreen`, `FallbackScreen`, `QrScreen`, `SettingsScreen`. The helper `gid` gives a widget its contract id (`ids` in the contract) as a semantics identifier: the resource-id on Android, the accessibilityIdentifier on iOS.
- `candidate-a-flutter/lib/src/ui/map_view.dart`: `MapView`, the map widget. Its state class implements `MapPort`.
- `candidate-a-flutter/lib/src/core/`: logic without widgets. `bundle_data.dart` (strict JSON parsers, `BundleData.load`), `search.dart`, `route.dart`, `steps.dart`, `style.dart`, `format.dart` (shown texts for steps, summary, trust state, anchor-code results, schedule), `policy.dart` (layout mode, update redirect rule), `strings.dart` (`Strings`), `crc32.dart`.
- `candidate-a-flutter/lib/src/lab/lab.dart`: `LabController` (lab hooks) and `decodeEnvelope`.
- `candidate-a-flutter/packages/g1_native/lib/g1_native.dart`: Dart side of the local plugin `g1_native` (`G1Native`, `G1Clock`).
- `candidate-a-flutter/packages/g1_native/android/src/main/kotlin/com/example/g1bench/g1native/G1NativePlugin.kt`: Android adapter of the plugin.
- `candidate-a-flutter/packages/g1_native/ios/g1_native/Sources/g1_native/G1NativePlugin.swift`: iOS adapter. Its Swift package is `candidate-a-flutter/packages/g1_native/ios/g1_native/Package.swift`.
- `candidate-a-flutter/android/`: Android project. `candidate-a-flutter/android/settings.gradle.kts` pins the Gradle plugins and includes `native-common/android` as project `:g1-native-common`. `candidate-a-flutter/android/build.gradle.kts` moves all build output to `candidate-a-flutter/build`. `candidate-a-flutter/android/app/src/main/kotlin/com/example/g1bench/candidatea/MainActivity.kt` is an empty `FlutterActivity` subclass. `candidate-a-flutter/android/app/src/main/AndroidManifest.xml` declares the `singleTop` launcher activity and no permission. Permissions, backup rules, the network security configuration and the AR and scanner activities are declared in `native-common/android/src/main/AndroidManifest.xml`.
- `candidate-a-flutter/ios/`: iOS project (`Runner.xcodeproj`, `Runner.xcworkspace`). `candidate-a-flutter/ios/Runner/AppDelegate.swift` registers the plugins. `candidate-a-flutter/ios/Runner/SceneDelegate.swift` forwards lab URLs to the plugin. `candidate-a-flutter/ios/Runner/Info.plist` declares the URL scheme `g1bench-a` and the camera usage text.
- `candidate-a-flutter/test/core_test.dart`: the unit suite of the application.
- `candidate-a-flutter/assets/strings/en.json` and `candidate-a-flutter/assets/strings/ar.json`: interface strings. They are byte copies of `contract/strings/en.json` and `contract/strings/ar.json`. `tools/sync_assets.py` makes the copies; with `--check` it verifies them. A unit test fails when a copy differs.
- `candidate-a-flutter/pubspec.yaml`, `candidate-a-flutter/pubspec.lock`, `candidate-a-flutter/g1-toolchain.json`, `candidate-a-flutter/analysis_options.yaml`: package list, lock file, SDK pin, lint configuration. `candidate-a-flutter/README.md` holds only the project template text.
- Shared pieces: `native-common/android` (Java library), `native-common/ios` (Swift package `G1NativeCommon`), `contract/contract.json` (ids, markers, lab hooks, contract texts, layout policy), `synthetic-data/out/` (bundle, trust store, fixtures, oracle files), `shared/lab/g1_lab_ca.pem` (certificate authority of the lab update endpoint), `ios-ci/` (scripts of the hosted iOS job).

## 3. Build and test

### 3.1 Android

- Tools: `flutter` is the Flutter tool of the pinned SDK. `gradle` is the launcher of the Gradle distribution pinned in `candidate-a-flutter/android/gradle/wrapper/gradle-wrapper.properties` (9.3.1). The tree has no wrapper binary: `candidate-a-flutter/android/.gitignore` excludes `gradle-wrapper.jar` and the `gradlew` scripts. On the lab host, the file `TOOLS.md` in the root of a work tree gives the commands of that host (the launcher paths).
- Preparation of the tree, in `candidate-a-flutter`: `flutter pub get --offline --enforce-lockfile`. It restores the package configuration from the lock file and the offline package cache, without network. Run it once before the first build or test, and again after `candidate-a-flutter/.dart_tool` was removed. The build and test commands below pass `--no-pub` and rely on it.
- Release build, in `candidate-a-flutter`: `flutter build apk --release --no-pub --split-debug-info=build/g1-symbols`. Output: `candidate-a-flutter/build/app/outputs/flutter-apk/app-release.apk`.
- Per-ABI build: `flutter build apk --release --no-pub --split-per-abi --split-debug-info=build/g1-symbols`. Outputs: `candidate-a-flutter/build/app/outputs/flutter-apk/app-<abi>-release.apk` for `arm64-v8a`, `armeabi-v7a` and `x86_64`.
- App bundle: `flutter build appbundle --release --no-pub --split-debug-info=build/g1-symbols`. Output: `candidate-a-flutter/build/app/outputs/bundle/release/app-release.aab`.
- Symbol files: `candidate-a-flutter/build/g1-symbols` and `candidate-a-flutter/build/app/outputs/mapping/release/mapping.txt`.
- The Flutter build runs every Gradle project of the application, the shared module included. All output is under `candidate-a-flutter/build`: the application in `candidate-a-flutter/build/app`, the shared module in `candidate-a-flutter/build/g1-native-common`.
- The build of the shared module copies `synthetic-data/out/bundle/G1SYN-1.0.0.zip` and `synthetic-data/out/app/trust_store.json` into generated assets after checking their SHA-256 against `synthetic-data/out/GENERATION_RECORD.json`. It copies `shared/lab/g1_lab_ca.pem` after checking a pinned SHA-256. A mismatch fails the build (tasks `g1Assets` and `g1LabCa` in `native-common/android/build.gradle.kts`).
- Unit suite of the application, in `candidate-a-flutter`: `flutter test --no-pub --reporter json`. The JSON report goes to standard output. The tests open files by relative path, so the working directory must be `candidate-a-flutter`.
- Unit suite of the shared native module inside this application's Gradle build, in `candidate-a-flutter/android`: `gradle :g1-native-common:testDebugUnitTest --offline --rerun-tasks`. JUnit XML reports: `candidate-a-flutter/build/g1-native-common/test-results/testDebugUnitTest`. Run the preparation step first.
- `candidate-a-flutter/android/settings.gradle.kts` reads the property `flutter.sdk` from `candidate-a-flutter/android/local.properties`. That file is not tracked. Gradle fails when the file or the property is missing (message for the property: "flutter.sdk not set in local.properties"). The Flutter tool writes the file when it configures or builds the Android project; run a Flutter build (or `flutter build apk --config-only`) once before the first direct `gradle` command in a fresh tree.
- Clean state: delete `candidate-a-flutter/build`, `candidate-a-flutter/.dart_tool`, `candidate-a-flutter/android/.gradle`, `candidate-a-flutter/android/build`, `candidate-a-flutter/android/app/.cxx` and `candidate-a-flutter/android/.kotlin`. Stop the Gradle daemons with `gradle --stop` in `candidate-a-flutter/android`.
- The release build type uses the debug signing configuration (`candidate-a-flutter/android/app/build.gradle.kts`).
- When the tree carries `harness/`, the same command lines are recorded in `harness/lib/exec/host_tasks.mjs` (tables `BUILD`, `UNIT` and `TREE_PREPARATION`, entry `A`).

### 3.2 iOS

- The lab host has no macOS toolchain. The iOS path is built and tested by a job on a hosted macOS runner (`runs-on: macos-26` in `ios-ci/workflow/g1-ios-feasibility.yml`).
- Entry point: `ios-ci/run-job.sh` with the job name `candidate-a-flutter`. It runs `ios-ci/probe-candidate-a-flutter.sh`. Shared functions are in `ios-ci/probe-common.sh`.
- Pins: Xcode `/Applications/Xcode_26.6.app`, simulator device type `iPhone-17` with runtime `iOS-26-5`, XcodeGen 2.46.0 (all in `ios-ci/probe-common.sh`), Node 24.13.1 (`ios-ci/prepare-data.sh`). The Flutter SDK is the archive named in `candidate-a-flutter/g1-toolchain.json` under `flutter_sdk.macos_arm64` (URL and SHA-256).
- A stage runs when every stage it needs has passed; otherwise it is recorded as skipped. A failed stage does not end the job. The job exits non-zero when a stage failed or was skipped. The stage records are in `candidate-a-flutter-stages.ndjson` in the directory `$EVIDENCE_DIR`, beside the logs of the stages.
- Stages in order:
  1. `environment`: selects the pinned Xcode, records the runner, creates and boots the simulator. Runs `ios-ci/prepare-data.sh`, which regenerates the synthetic dataset and compares it with `synthetic-data/out/GENERATION_RECORD.json`. `ios-ci/prepare-assets.sh` then copies the bundle, the trust store and the lab CA into `native-common/ios/Sources/G1NativeCommon/Resources/g1` (not tracked). Fetches XcodeGen. Downloads the Flutter SDK archive and checks its SHA-256.
  2. `resolve` (needs `environment`): `flutter pub get --enforce-lockfile` in `candidate-a-flutter`. This is the default mode `G1_RESOLUTION=locked`; the mode `update` runs `flutter pub get` without the flag.
  3. `configure` (needs `resolve`): `flutter build ios --config-only --simulator --debug --no-pub`. Then `xcodebuild -list` must list the scheme `Runner` of `candidate-a-flutter/ios/Runner.xcworkspace`.
  4. `unit` (needs `resolve`): `flutter test --no-pub` with a JSON file reporter. It is the same suite as in 3.1.
  5. `build-simulator` (needs `configure`): `flutter build ios --simulator --debug --no-pub`. App: `candidate-a-flutter/build/ios/iphonesimulator/Runner.app`. Debug is the only mode Flutter builds for a simulator.
  6. `linkage-simulator` (needs `build-simulator`): `otool -L` over the app. It fails unless MapLibre and `ARKit.framework` are linked.
  7. `launch` (needs `build-simulator`): installs and launches the app on the simulator and waits for the marker `app.ready`. It passes only when `app.start`, `bundle.loaded` with `state=VALID`, `map.style.loaded` and `app.ready` appear in this order.
  8. `e2e` (needs `launch`): copies `synthetic-data/out/qr/A01.png` into the app folder `Documents/g1/import/`, generates the test project of `ios-ci/e2e` with XcodeGen and runs the UI tests of `ios-ci/e2e/G1E2ETests/FlowTests.swift` against bundle id `com.example.g1bench.candidatea` and URL scheme `g1bench-a`.
  9. `build-device` (needs `configure`): `flutter build ios --release --no-codesign --no-pub`. App: `candidate-a-flutter/build/ios/iphoneos/Runner.app`.
  10. `linkage-device` (needs `build-device`): the same linkage check on the device app.
  11. `inventory` (needs `build-device`): lists the checked-out Swift packages with their licence files. It fails when MapLibre is not among them.
  12. `lock-check` (needs `resolve`): the lock files must be tracked and unchanged after the job.
- Tracked and checked lock files: `synthetic-data/package-lock.json`, `candidate-a-flutter/pubspec.lock`, `candidate-a-flutter/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `candidate-a-flutter/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. No other `Package.resolved`, `Podfile.lock`, `pubspec.lock` or `package-lock.json` may appear untracked or changed in the tree.
- The main UI test types `SB1-F1-R001`, opens result `D001`, checks the details and a schedule row, computes a route, taps the AR button and expects the text fallback, goes back, switches the language and expects the results to stay. Two more tests cover the largest text size and an injected anchor code sent with the lab URL (hook `qr.inject`). Three tests only record facts: burst typing, the accessibility audit and control sizes.

## 4. How it works

**State.** All state is in one object: `AppState` in `candidate-a-flutter/lib/src/app_state.dart`, a `ChangeNotifier`. `main()` creates it and every screen receives it through its constructor. `G1App` in `candidate-a-flutter/lib/src/ui/screens.dart` wraps the tree in a `ListenableBuilder`, so each `notifyListeners()` rebuilds the screens. The fields hold the language (`lang`), the bundle (`bundleInfo`, `data`, `index`, `graph`, `nodes`), the screen stack (`stack`), the floor, the search (`query`, `results`), the route (`origin`, `stepFree`, `blocked`, `route`, `steps`, `summary`), the last anchor-code outcome and the update state. Widgets keep no domain state. The lab hooks call the same handlers as the screens.

**Screens and navigation.** Screens are not pushed as routes. `AppState.stack` is a list of `ScreenEntry` values with a `ScreenKind` (`home`, `details`, `route`, `fallback`, `qr`, `settings`). `_Root` shows the screen of the last entry above the home screen. The home screen and its map stay alive underneath (`Offstage`, `ExcludeFocus`, `TickerMode`). `openDetails`, `openRoute`, `openAr`, `_showQr` and `openSettings` push an entry. `back()` removes the last entry and `goHome()` clears the stack. The system back action calls `back()` through `PopScope`. A push writes the marker `screen.shown` with `screen=` `S04` (details), `S07` (route), `S09` (fallback), `QR` or `SETTINGS`. Reaching the home screen again writes `S01`.

- `HomeScreen`: trust line, search field and button, result list, floor buttons, map, and the actions language, scan and data-and-trust. A result row opens the details.
- `DetailsScreen`: code, name, building, floor, reachability, schedule rows, and the buttons for directions and "show on map".
- `RouteScreen`: start entrance, step-free switch, compute button, trust line, then summary and steps, or the reject text. The AR button is shown only for a computed path.
- `openAr()` starts the native AR screen when `arAvailability` is `SUPPORTED`. Otherwise it shows `FallbackScreen` with the same steps as text and writes `fallback.shown`.
- `QrScreen` shows the outcome of a scan. `SettingsScreen` shows version, validity, trust state, the update button and the last import result.

**Search and route.** `submitSearch()` calls `SearchIndex.search(query)` and writes `search.result`. `computeRoute()` calls `RouteGraph.route(origin, node, stepFree:, blocked:)`. For a path it calls `routeSteps` and sends the path geometry to the map source `route`. It writes `route.result`. Without a valid bundle it answers `REJECT_UNTRUSTED`.

**Ready sequence at launch.**
1. When the plugin attaches, the shared module is initialised with app id `A`. It loads the compiled-in trust store, opens the bundle store and writes `app.start`.
2. `AppState.boot()` calls `G1Native.ensureBundle()`. The shared module loads the active bundle and verifies it again (signature, hashes, validity, trusted time). When no bundle is stored it first imports the embedded `G1SYN-1.0.0.zip` through the same check and writes `bundle.result` with `source=embedded`. It writes `bundle.loaded` with `state` and `version` and returns the bundle info as JSON (`state`, `version`, `dir`, validity times).
3. `_loadData()` continues only for the state `VALID`. `BundleData.load` reads `destinations.json`, `graph.json`, `schedule.json`, `route_cases.json`, `query_corpus.json`, `style.json` and `geometry.geojson` directly from the verified directory `dir`. `_loadData()` then builds the search index (`SearchIndex`), the route graph (`RouteGraph`) and the initial map style (`buildStyle`). A parse error leaves the data empty and writes `bundle.loaded` with `state=PARSE_ERROR`.
4. The home screen is built with the search field enabled. It calls `homeShown()` at the first frame callback after that frame.
5. The map loads the style. `_onStyleLoaded` calls `onStyleLoaded()`, which writes `map.style.loaded` with the floor.
6. `_checkReady()`: when the bundle is valid, the index exists, the home screen is shown and the style is loaded, the next frame callback calls `G1Native.reportReady`. The shared module writes `app.ready` once per process. On Android it also calls `Activity.reportFullyDrawn()`.
7. `LabController.start()` then takes the lab command of the launch, if there is one.
8. A return to the foreground calls `onResumed()`, which writes `app.resume.ready`.

**Map.** `MapView` uses the package `maplibre_gl` (widget `MapLibreMap`, a platform view). The style string comes from `buildStyle` in `candidate-a-flutter/lib/src/core/style.dart`. Every `g1bundle://` prefix of the bundle file `style.json` becomes a file URL of the bundle directory, so geometry, glyphs and sprites load from local files. The initial camera is the `center` and `zoom` of the style. Rotation and tilt gestures are off. `AppState` talks to the map through `MapPort`: `setFloor` (layer filters from `floorFilters`), `setLanguage` (layer `room-labels`), `setRoute` (GeoJSON source `route`), `moveCamera`, `reload` (new style after a bundle change), `clear` (empty style) and `inspect`. `lonOf` and `latOf` in `app_state.dart` convert graph millimetres to degrees.

**Language.** `main()` parses both string files into `Strings` objects. `AppState.lang` starts as `ar`. `setLang` and `toggleLang` change it, write `lang.changed` and call `setLanguage` on the map. Screens read texts with `state.s.t(key, params)`. A missing key is shown as `[key]`. `G1App` sets the text direction from the string `_meta.direction`. The state object is not replaced, so the search, the results and the screen stack stay.

**Layout policy.** `layoutMode(width, height, fontScale)` in `candidate-a-flutter/lib/src/core/policy.dart` returns `regular` when width / fontScale is at least 360 and height / fontScale is at least 600. Otherwise it returns `compact`. `_HomeScreenState.build` passes the window size without the system insets (`MediaQuery` size minus `viewPadding`) and the text scale. Regular: one column; the result region gets up to two fifths and the map three fifths of the free height, and the result list scrolls inside its region. Compact: the whole home screen is one scroll view, every result row is laid out, and the map height is `compactMapHeight(windowHeight)`: half the window height, at most 240. One `MapView` with a `GlobalKey` serves both modes. The other screens are a `ListView` in both modes.

## 5. The native boundary

### 5.1 Where the boundary is defined

- Mechanism: Flutter platform channels, declared in `candidate-a-flutter/packages/g1_native/lib/g1_native.dart`. `MethodChannel('g1/native')` carries the calls. `EventChannel('g1/events')` carries AR events and lab commands. `EventChannel('g1/n2r')` carries the native-to-runtime messages of the echo workload. Every call is asynchronous; there is no synchronous path.
- Dart side: class `G1Native` (static methods over the private helper `_call`). Android side: `G1NativePlugin.kt` (`onMethodCall`, then `dispatch`). iOS side: `G1NativePlugin.swift` (`handle(_:result:)`, then `dispatch`). The paths are in section 2.
- Both adapters call the facade `G1Native` of the shared module: `native-common/android/src/main/java/com/example/g1bench/common/G1Native.java` and `native-common/ios/Sources/G1NativeCommon/G1Native.swift`.
- Build links: the Android adapter depends on `project(":g1-native-common")`, which `candidate-a-flutter/android/settings.gradle.kts` maps to `native-common/android`. The iOS adapter's `Package.swift` finds `native-common/ios` from its own real location. Both use relative paths, so the application directory and `native-common/` must keep their relative position.
- Encoding: the channels are created without a codec argument and use the default codec of the framework. Arguments are one map of named values. Bytes are `Uint8List` in Dart, `ByteArray` in Kotlin and `FlutterStandardTypedData` in Swift. Structured results of the shared module cross as JSON strings and are decoded with `jsonDecode` in Dart (`ensureBundle`, `bundleInfo`, `validateQr`). `echoAsync` returns two 64-bit integers.
- Checks in both adapters before the shared module is called: a wrong or missing argument gives the error code `BAD_ARGUMENT`. A string or byte field above 64 KiB gives `PAYLOAD_TOO_LARGE` (`importBundleBytes` allows 64 MiB). A file error of the module gives `IO`. Dart receives these as `PlatformException`. An unknown method is answered as not implemented, which Dart receives as `MissingPluginException`.
- Events back: the adapters send maps to the `g1/events` sink on the main thread. Events sent before Dart listens wait in `pendingEvents`. The types are `command` (`name`, `args`) and `ar` (`requestId`, `event` as JSON text). The only listener is in `LabController.start`; it passes AR events to `AppState.onArEvent`. `g1/n2r` carries `seq`, `sent`, `payload` and a last record with `done`.
- The clock does not cross a channel. `G1Clock.nowNanos` reads the monotonic clock in the process through `dart:ffi` (`CLOCK_BOOTTIME` on Android, `CLOCK_MONOTONIC_RAW` on iOS). The shared module stamps its markers with the same clock.
- Method sets: the Android adapter handles 30 method names. The iOS adapter handles the same names except `removeBundles`. The Dart class has a method that sends each of these names except `nowNanos`: its own `nowNanos` reads the monotonic clock through the foreign-function interface and sends no message.

### 5.2 Who owns what

"Shared" means a class of the shared native module, in `native-common/android/src/main/java/com/example/g1bench/common/` or `native-common/ios/Sources/G1NativeCommon/`. "Adapter" means `G1NativePlugin.kt` or `G1NativePlugin.swift` of this application. Every call passes through the adapter; the owner is the class that does the work.

| Capability | Runtime side (Dart) | Android owner | iOS owner |
|---|---|---|---|
| Map view | `MapView` in `map_view.dart`; style functions in `style.dart` | package `maplibre_gl`; this tree has no map code for Android | package `maplibre_gl` with the Swift package `maplibre-gl-native-distribution`; this tree has no map code for iOS |
| Bundle trust and storage | `AppState.boot`, `importBundleFile`, `rollback`, `removeBundles`, `_afterBundleChange`; `BundleData.load` reads the verified directory | shared: `BundleStore`, `BundleVerifier`, `StoredZip`, `TrustStore`, `TrustedClock`, `Ed25519` | shared: the same class names (`Ed25519` is in `Hex.swift`); no bundle removal |
| Anchor-code (QR) decoding and scanner | `AppState.scanQr`, `injectQr`; `QrScreen`; `qrText` | shared: `QrScannerActivity` (CameraX), `QrDecode` and `QrImages` (ZXing), `QrValidator` | shared: `QrScannerViewController` (AVFoundation), `QrDecode` (Core Image), `QrValidator` |
| AR session and AR screen | `AppState.openAr`, `onArEvent`, `dropAr`; `FallbackScreen` | shared: `ArActivity`, `ArBackground`, `ArSupport` (ARCore) | shared: `ArViewController` and `ArSupport` in `ArViewController.swift` (ARKit) |
| Camera permission | none; Dart only receives `PERMISSION_DENIED`, `CAMERA_UNAVAILABLE` or `CANCELLED` | shared: asked in `QrScannerActivity` and `ArActivity`; declared in the manifest of the shared module | shared: asked in `QrScannerViewController`; usage text in `candidate-a-flutter/ios/Runner/Info.plist` |
| Bridge echo workload | `LabController._benchBridge`, `_r2n`, `_n2r`, `_localEcho`; `Crc32` | shared: `BridgeWorker`, `Echo` | shared: `BridgeWorker` and `Echo` in `BridgeWorker.swift` |
| Lab command transport | `LabController.start`, `_drain`, `_exec`; `decodeEnvelope` | shared: `LabCommand.fromIntent`; adapter: `commandOf`, `onNewIntent` | shared: `LabCommand.fromLaunchArguments`, `fromURL`; adapter: `handle(url:)`, called by `SceneDelegate` |
| Markers and logging | `AppState._mark`, `LabController._mark`, `G1Clock` | shared: `G1Trace` (logcat tag `G1MARK`) | shared: `G1Trace` (unified log and standard error) |
| Update download | `AppState.update` with the `dart:io` `HttpClient`; `redirectTarget` in `policy.dart` | shared: `G1Native.labCa` gives the CA, `importBundleBytes` installs | shared: the same two facade methods |
| Lab files (`import`, `out`) | `G1Native.writeOut`, `readImportText` | shared: `G1Files` | shared: `G1Files` |
| Session marker and crash triggers | `LabController._exec`, `_crash` | shared: `SecureSession`, `CrashHooks` | shared: `SecureSession`, `CrashHooks` |

### 5.3 Adding or changing an operation across the boundary

1. Choose the method name and the argument names. The arguments travel as one map.
2. Dart: add a static method to `G1Native` that calls `_call<T>('name', {...})` and converts the result. Example: `validateQr` sends `{'payload': payload}` and decodes the returned JSON string.
3. Android: add a branch `"name" ->` to `dispatch` in `G1NativePlugin.kt`. Read arguments only with the helpers `str`, `bytes`, `int`, `long` and `bool`; they produce `BAD_ARGUMENT` and `PAYLOAD_TOO_LARGE`. Call the facade and answer with `result.success`. For a callback from another thread answer inside `onMain` (see `echoAsync` and `scanQr`).
4. iOS: add `case "name":` to `dispatch` in `G1NativePlugin.swift` with the same names and checks (`str`, `bytes`, `int`, `bool`). For a callback answer on the main queue (see `echoAsync`).
5. New native behaviour belongs in the shared module, in both facades (`G1Native.java` and `G1Native.swift`). Sibling applications use the same module, so keep the existing signatures. `native-common/android/consumer-rules.pro` keeps the public members of the Java facade in shrunk builds.
6. A result that arrives later can also be sent as an event: call `emit` with a map that has a `type`, and handle that type in the listener in `LabController.start`.
7. Call the new Dart method from an `AppState` handler, so that the screens and the lab hooks share it.
8. For a new lab hook also add the name to `labCommands` and a `case` to `LabController._exec`, to `LabCommand.COMMANDS` (Java) and `LabCommand.commands` (Swift), and to `lab_hooks.commands` in `contract/contract.json`.

Tests that cover the message decoder:
- `decodeEnvelope` in `candidate-a-flutter/lib/src/lab/lab.dart` is the runtime decoder of the hook envelope `{"method": name, "args": {...}}`. The case `lab hooks: registered commands, UI script and envelope decoder match the contract` in `candidate-a-flutter/test/core_test.dart` checks its accept and reject codes and compares `labCommands` with the contract.
- The native transport check `LabCommand` is covered by `transportAdmitsExactlyTheContractCommands` in `native-common/android/src/test/java/com/example/g1bench/common/LabCommandTest.java` and by `testLabCommandsAreRegisteredBoundedJsonObjects` in `native-common/ios/Tests/G1NativeCommonTests/TrustContractTests.swift`.
- The argument checks of the two adapters have no unit test; the plugin package has no test directory. On a device the hook `bridge.attack` exercises them (cases `BRG03` unknown method, `BRG04` oversized field, `BRG05` wrong types, in `LabController._attack`). The hook `fuzz` with target `FUZ03` feeds a corpus to `decodeEnvelope`.

## 6. Data contracts and where each is implemented

The Dart code is compiled into both the Android and the iOS application. One Dart file therefore implements a contract on both OS paths; there is no second copy to keep in step. The contracts of the shared module have one Java and one Swift implementation. Dart files below are in `candidate-a-flutter/lib/src/core/`; shared module files are in the two directories named in 5.2.

| Contract | File(s) on the Android path | File(s) on the iOS path |
|---|---|---|
| G1-SEARCH-1.0 | `search.dart`: `normalize`, `tokens`, `codeKey`, `SearchIndex.search` | the same Dart file |
| G1-ROUTE-1.0 | `route.dart`: `RouteGraph.route`; graph parser `parseGraph` in `bundle_data.dart` | the same Dart files |
| G1-ROUTE-STEPS-1.0 | `steps.dart`: `routeSteps`, `RouteStep`, `RouteSummary`, `metres`; shown text in `format.dart`: `stepText`, `summaryText` | the same Dart files |
| G1-STYLE-1.0 | `style.dart`: `buildStyle`, `withFloor`, `floorFilters`, `textField`, `routeFeatures`; applied in `candidate-a-flutter/lib/src/ui/map_view.dart` | the same Dart files |
| G1-LAYOUT-1.0 | `policy.dart`: `layoutMode`, `compactMapHeight`; applied in `_HomeScreenState.build` in `candidate-a-flutter/lib/src/ui/screens.dart` | the same Dart files |
| G1-QR-1.0 | shared module: `QrValidator.java`; decoding in `QrDecode.java` and `QrImages.java`; Dart only shows the outcome (`qrText`) | shared module: `QrValidator.swift`; decoding in `QrDecode.swift` |
| G1-TRUST-1.0 | shared module: `BundleVerifier.java`, `BundleStore.java`, `StoredZip.java`, `TrustStore.java`, `TrustedClock.java`, `TrustCodes.java`; Dart only shows the state (`trustText`) | shared module: the Swift files of the same names |
| Lab hook names and envelope | `candidate-a-flutter/lib/src/lab/lab.dart`: `labCommands`, `decodeEnvelope`; shared module: `LabCommand.java` | the same Dart file; shared module: `LabCommand.swift` (20 of the 25 names) |
| Marker line format | shared module: `G1Trace.java` | shared module: `G1Trace.swift` |
| Update transfer rule | `policy.dart`: `redirectTarget`, `inLabOrigin`; `AppState.update` | the same Dart files |

The rule texts are in `contract/contract.json`: `data_contract_text` (search, route, style), `route_steps.rule` and `layout`. The QR and trust rules are written in the header comments of `QrValidator.java` and `BundleVerifier.java`. Reference implementations of search, route and steps are `synthetic-data/src/search.mjs`, `synthetic-data/src/routes.mjs` and `synthetic-data/src/steps.mjs`.

## 7. Tests

- `candidate-a-flutter/test/core_test.dart` holds the 8 cases of the application's suite. It opens `synthetic-data/out/bundle/G1SYN-1.0.0.zip` with its own helper `storedZip` and takes the bundle files from it.
  - `G1-SEARCH-1.0 agrees with the oracle on all 500 queries`: `SearchIndex.search` for every entry of `query_corpus.json`. Expected outcome and ids: `synthetic-data/out/oracle/search_oracle.json` (`results`, same order).
  - `G1-ROUTE-1.0 and G1-ROUTE-STEPS-1.0 agree with the oracle on all 30 cases`: this is the test that compares routes and steps with the oracle. For every case of `route_cases.json` it runs `RouteGraph.route` and, for a path, `routeSteps`. Expected `outcome`, `nodes`, `length_mm`, `steps` and `summary`: `synthetic-data/out/oracle/route_oracle.json` (`results`, same order). Steps and summary are compared as the JSON text of `RouteStep.toJson` and `RouteSummary.toJson`.
  - `parsers reject malformed input with FormatException only`: `parseGraph` and `parseDestinations` with broken inputs.
  - `G1-STYLE-1.0 transforms`: `buildStyle` and `floorFilters` on the bundle file `style.json` (file URLs, floor filters, label field).
  - `strings: same keys in both languages and every referenced key exists`: both asset files have the same keys and equal the files in `contract/strings/` byte for byte; the text helpers of `format.dart` find their keys.
  - `lab hooks: registered commands, UI script and envelope decoder match the contract`: see 5.3.
  - `layout policy and update redirect rule match the contract`: the constants of `policy.dart` and the vectors `layout.mode_vectors` and `layout.map_height_vectors` of the contract against `layoutMode` and `compactMapHeight`; `redirectTarget` and `inLabOrigin`.
  - `runtime CRC-32 equals the standard check value`: `Crc32.of`.
- Shared module on Android, run by the Gradle command of 3.1: `native-common/android/src/test/java/com/example/g1bench/common/TrustContractTest.java` (9 cases: bundle and fixture codes, untrusted time, container rules, activation and rollback, removal, clock rollback, QR fixtures, strict encodings, echo) and `LabCommandTest.java` beside it. Inputs and expected data: the bundle archive, `synthetic-data/out/fixtures/FIXTURES.json` with the archives beside it, `synthetic-data/out/oracle/qr_fixtures.json`, `synthetic-data/out/app/trust_store.json` and `contract/contract.json`.
- Shared module on iOS: `native-common/ios/Tests/G1NativeCommonTests/` (`TrustContractTests.swift`, `FacadeTests.swift`, `QrDecodeTests.swift`). The job of this application does not run them; `ios-ci/probe-native-common.sh` does.
- UI flow on the iOS simulator: `ios-ci/e2e/G1E2ETests/FlowTests.swift` (stage `e2e` in 3.2).
- `candidate-a-flutter/ios/RunnerTests/RunnerTests.swift` is the empty template test; no stage runs it. The tree has no widget tests.
- The lab refers to unit cases by name: the first three cases above and every case of the class `com.example.g1bench.common.TrustContractTest`. The names are therefore part of the interface.

## 8. Diagnosing a problem

- Markers. The application writes one line per event: `G1MARK v=1 app=A seq=<n> name=<name> t=<native ns> rt=<runtime ns or -> key=value ...`. Values are URL-encoded and are ids, codes or numbers only. `seq` counts the markers of the process. Android: logcat tag `G1MARK`, priority INFO (`G1Trace.java`). iOS: unified log, subsystem `com.example.g1bench`, category `G1MARK`, and also standard error (`G1Trace.swift`). The names are listed under `markers.names` in `contract/contract.json`.
- Marker sources. Runtime: `AppState._mark` and `LabController._mark` call `G1Native.mark`. Shared module: `app.start`, `app.ready`, `app.resume.ready`, `bundle.result`, `bundle.loaded`, `qr.validated`, `ar.state`, `ar.arrow`, `session.state`, `command.received`, `command.rejected`, and `crash.trigger` for the native crash cases.
- Lab hooks. The names and arguments are the entries of `lab_hooks.commands` in `contract/contract.json`; the same names are in `labCommands` in `lab.dart`. `LabController._exec` maps each name to a handler. On Android a hook is an explicit start of the launcher activity with two string extras: `am start -n com.example.g1bench.candidatea/.MainActivity --es g1.cmd <name> --es g1.args '<JSON object>'`, run in the device shell through `adb shell`. Send ASCII only and write other characters as `\u` escapes. The arguments may have at most 16 KiB.
- The lab tooling installs an APK on a device with `adb install -r -t <apk>`.
- A running app receives the hook through `onNewIntent` (the activity is `singleTop`). A hook in the launch intent is held by the adapter and run after the ready state; `LabController.start` waits for that state for at most 60 s.
- Hook results. A hook with a `run_id` writes `<run_id>.json` into the lab directory `out`. Input files are read from the lab directory `import`. On Android both are in the app-specific external files directory: `/sdcard/Android/data/com.example.g1bench.candidatea/files/g1/out` and `/sdcard/Android/data/com.example.g1bench.candidatea/files/g1/import`. File names use the characters `[A-Za-z0-9._-]` only.
- Hook errors. The shared module writes `command.received`, or `command.rejected` with `reason` `unknown_command`, `args_size` or `args_json`. `LabController` writes `command.rejected` with `reason=runtime_envelope`, or `command.failed` with `cmd` and `error` (the Dart exception type).
- Hooks that help: `nav.home`, `nav.details` (`destination`), `nav.route` (`case`, or `destination`, `origin`, `step_free`), `lang.set` (`lang`), `bundle.import` (`file`), `bundle.rollback`, `qr.inject` (`file`), `ar.inject` (`script`, `case`), `bridge.attack` (`run_id`, `case`). Android only: `search.set` (`text`), `map.inspect` (`run_id`), `map.camera`, `bundle.remove`, `a11y.seed`. The hook `bench.search-route` (`run_id`, `kind`) runs the 500 corpus searches and the 30 route cases of the bundle through `submitSearch` and `computeRoute` and writes outcomes, ids, nodes, `length_mm`, steps and summary to its result file.
- On iOS the transport is the launch arguments `-g1.cmd <name> -g1.args <json>` or, for a running app, the URL `g1bench-a://cmd?name=<name>&args=<url-encoded json>`.
- Wrong search result: `candidate-a-flutter/lib/src/core/search.dart` (`normalize`, `tokens`, `codeKey`, `SearchIndex.search`). A text whose code key has the form of a room code (`SB<n>F<n>R<n>`) is matched by code only. Any other text needs every token in the token set of the destination. The data is `destinations.json`, parsed by `parseDestinations`. Compare with `synthetic-data/out/oracle/search_oracle.json` and `synthetic-data/src/search.mjs`. The unit test names the failing corpus id.
- Wrong route: `candidate-a-flutter/lib/src/core/route.dart` (`RouteGraph.route` and its private distance pass with the heap `_Heap`; ties take the smallest predecessor id). Input: `graph.json` through `parseGraph`, plus the flags `stepFree` and `blocked`. Compare with `synthetic-data/out/oracle/route_oracle.json` and `synthetic-data/src/routes.mjs`.
- Wrong step or summary: the step list comes from `routeSteps` in `candidate-a-flutter/lib/src/core/steps.dart` (edge kinds `corridor`, `spur`, `outdoor`, `entrance`, `stairs`, `elevator`; whole metres by `metres`). The shown text comes from `stepText` and `summaryText` in `candidate-a-flutter/lib/src/core/format.dart` with the string keys `route.step.*` and `route.summary`. `RouteScreen` and `FallbackScreen` use the same functions. The route line on the map comes from `routeFeatures` in `style.dart`.
- Wrong layout at a window size: `layoutMode` and `compactMapHeight` in `policy.dart` and their use in `_HomeScreenState.build`. The expected mode for a size is in `layout.mode_vectors` of the contract. The header is the Material `AppBar`: it keeps one line and shortens a long title.
- A bridge call fails: read the code of the `PlatformException`. `BAD_ARGUMENT`: wrong or missing argument, or no attached activity on Android (`reportReady`, `scanQr`, `startAr`). `PAYLOAD_TOO_LARGE`: a field above 64 KiB. `IO`: file error in the shared module, for example a refused lab file name or no verified bundle. `MissingPluginException`: the adapter of this OS has no branch for the method name. Check that the method name and the argument names are equal in `g1_native.dart`, `G1NativePlugin.kt` and `G1NativePlugin.swift`.
- Bundle or trust state: the line `home.trust`, the screen "data and trust", and the markers `bundle.loaded` and `bundle.result` (`code` is a constant of `TrustCodes`).

## 9. Dependencies and versions

- Flutter SDK: `candidate-a-flutter/g1-toolchain.json` pins version 3.47.5 (stable) with the archive URL and SHA-256 for `macos_arm64` and `windows_x64`.
- Dart packages: `candidate-a-flutter/pubspec.yaml` (SDK constraint `^3.13.4`; `maplibre_gl` 0.27.1, `unorm_dart` 0.3.2, the path package `g1_native`; for development `flutter_test` and `flutter_lints` `^6.0.0`). Resolved versions and hashes: `candidate-a-flutter/pubspec.lock`. `candidate-a-flutter/packages/g1_native/pubspec.yaml` pins `ffi` 2.2.0.
- Gradle: distribution 9.3.1 (`candidate-a-flutter/android/gradle/wrapper/gradle-wrapper.properties`). Android Gradle plugin 9.1.0 and Kotlin plugin 2.4.0 (`candidate-a-flutter/android/settings.gradle.kts`). JVM settings: `candidate-a-flutter/android/gradle.properties`.
- Android levels: `minSdk` 24 and Java 17 in `candidate-a-flutter/android/app/build.gradle.kts`. The compile SDK, the target SDK and the NDK version come from the Flutter Gradle plugin. The plugin and the shared module compile with SDK 36.
- Libraries of the shared module on Android (`native-common/android/build.gradle.kts`): ARCore 1.56.0, ZXing core 3.5.4, BouncyCastle `bcprov-jdk18on` 1.82, CameraX 1.5.1, `androidx.activity` 1.11.0. Its tests use JUnit 4.13.2 and `org.json` 20250517.
- iOS: deployment target 16.0 (`candidate-a-flutter/ios/Runner.xcodeproj/project.pbxproj` and both `Package.swift` files). The Swift packages resolve to the two tracked `Package.resolved` files named in 3.2; they pin `maplibre-gl-native-distribution` 6.28.0. The project has no Podfile. The pins of the job are listed in 3.2.
- Synthetic data generator: `synthetic-data/package.json` and `synthetic-data/package-lock.json` (Node 24.13.1).
- Identifiers: Android application id and iOS bundle id `com.example.g1bench.candidatea`; package version `0.1.0+1` in `candidate-a-flutter/pubspec.yaml`.
- Permissions of the Android app: the merged manifest holds what the shared native module declares (`CAMERA`, `INTERNET`) and what the manifest of the map engine declares. `candidate-a-flutter/android/app/src/main/AndroidManifest.xml` removes the two location permissions of the map engine (`tools:node="remove"`), because the application never reads the device location; the two network state permissions of the map engine stay. `contract/contract.json` (`security.permissions`) lists the permissions the release app may request. A dependency upgrade can add a permission to the merged manifest: compare the list after every upgrade.

## 10. Known limits

- Light appearance only (`platform_floor.appearance` in the contract; `Brightness.light` in `G1App`; `UIUserInterfaceStyle` in `candidate-a-flutter/ios/Runner/Info.plist`).
- Floors 1 to 3 only: `AppState.setFloor` ignores other values.
- AR: only a device whose availability is `SUPPORTED` opens the native AR screen. An Android emulator image without ARCore and the iOS simulator report `UNSUPPORTED`, so the AR button leads to the text fallback. No spatial fixture exists, so a real AR session never establishes a pose and never shows the arrow. The arrow appears only in the injected mode of the hook `ar.inject`.
- A valid anchor code gives an identity only. It never establishes position, floor or arrival (`pose_established` is always false).
- Lab hooks are compiled into every build of this tree: `BuildFlags.LAB` (Java) and `BuildFlags.lab` (Swift) are the constant true.
- Five hooks exist on Android only: `search.set`, `a11y.seed`, `bundle.remove`, `map.inspect`, `map.camera`. The iOS transport does not accept them and the iOS adapter has no `removeBundles` method.
- Platform channels have no synchronous path. The hook `bench.bridge` answers `UNSUPPORTED` for a `sync` workload.
- Network: the Dart code opens a connection only in `AppState.update`, to the lab origin `https://localhost:8443/`. Any other URL is refused with `REJECT_URL`. Redirects are followed by hand, at most 5, inside that origin only. A download above 64 MiB fails.
- Size bounds: 64 KiB per string or byte field across the channel, 16 KiB of hook arguments, 16 MiB of text per parsed JSON file (`maxJsonChars`).
- Markers carry ids, codes and numbers only. No entered text, payload or route is logged.
- The release APK is signed with the debug configuration.
- On an iOS simulator Flutter builds the application in debug mode only.
- The Material app bar keeps the title on one line and shortens it when the actions need the space (`layout.header` in the contract).
