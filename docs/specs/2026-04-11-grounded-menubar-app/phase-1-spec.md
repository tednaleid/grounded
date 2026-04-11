# Phase 1: Scaffold + just-bootstrap Infrastructure

**Parent contract:** [`contract.md`](./contract.md)

**Goal:** Empty buildable Swift menubar app with the hexagonal directory layout, the full just-bootstrap standard, a minimal `just inspect-state` that works on an empty app, and `just check` green in CI. Ted can tag 0.0.x if he wants — proves the pipeline works before any feature work.

## Steps

1. **Clean out the PoC.** Delete `check_charger.py`, `.env`, `.env.example`. Update `.gitignore` to remove the `.env` line and add `/tmp/grounded-build`, `.DS_Store`, `*.xcodeproj/xcuserdata/`, `*.xcodeproj/project.xcworkspace/xcuserdata/`. Keep `.llm`. Commit as "remove python poc in favor of swift app".

2. **Create `project.yml`** — XcodeGen config modeled on `../montty/project.yml`. Target macOS 14.0. **Swift language version: Swift 6.** Strict concurrency: `complete`. Single app target `grounded`, bundle ID `com.tednaleid.grounded`, `LSUIElement=true`, entitlements `Resources/grounded.entitlements`, hardened runtime. Three test targets: `GroundedCoreTests`, `GroundedAdapterTests`, `GroundedIntegrationTests` — all using the Swift Testing framework (not XCTest). Source groups mirror the `Sources/` layout. Verify the project opens in Xcode **26.4** and builds cleanly with zero strict-concurrency warnings.

3. **Create the hexagonal directory skeleton.** Every directory in the Repository Layout section of `contract.md` exists, even if empty. Each folder gets a `.gitkeep` if it has no files yet.

4. **Create the minimal buildable app.** Just enough code for the app to launch, show a gray `bolt.car.circle` icon, and respond to `just inspect-state`:
   - `Sources/Core/ChargerState.swift` with the enum (no logic yet)
   - `Sources/Core/Ports/StateObserver.swift` protocol
   - `Sources/App/GroundedApp.swift` @main scene
   - `Sources/App/AppDelegate.swift` — creates NSStatusItem with `bolt.car.circle` tinted `.secondaryLabel`, 2-item menu ("grounded (empty)", "Quit"), boots the InspectServer in `#if DEBUG`
   - `Sources/Adapters/Debug/InspectServer.swift` — minimal HTTP server (NWListener) exposing just `GET /state` returning `{"state": "unknown", "hasCredentials": false}`
   - `Resources/Info.plist` — LSUIElement=true, version 0.0.1, bundle ID
   - `Resources/grounded.entitlements` — unsandboxed, hardened runtime

5. **Create `scripts/generate-icon.swift`.** Small SwiftUI-based renderer that loads `bolt.car.circle`, tints it systemGreen, and writes PNGs at all required AppIcon sizes to `Resources/Assets.xcassets/AppIcon.appiconset/`. Include a Justfile recipe `just icon` that runs it. Run once and commit the generated PNGs.

6. **Write the first red/green pair** as a smoke test for the core test target: a Swift Testing `@Test` in `Tests/CoreTests/ChargerStateTests.swift` asserting `#expect(ChargerState.unknown != ChargerState.signedOut)`. This proves the Swift Testing framework is wired up, the core test target compiles, and the core runs with zero framework deps. Red first (the file doesn't exist), green second (add the assertion, watch it pass).

7. **Run `xcodegen generate`.** Confirm it opens and builds in Xcode.

8. **Invoke `/just-bootstrap`** against the now-detectable Swift macOS project. It generates `Justfile`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `scripts/setup-homebrew-tap.sh`, `CLAUDE.md` build/test section, pre-commit hook. Verify:
   - It detects the app as a macOS cask target and produces a cask-updating release workflow pointed at `tednaleid/homebrew-grounded`
   - The CI and release workflows use a runner image with **Xcode 26.x**. If just-bootstrap's template predates Xcode 26, modify the workflow to either use `macos-15` / `macos-latest` with an explicit Xcode select step (`sudo xcode-select -s /Applications/Xcode_26.app`) OR install via `xcodes install 26.4` action. Flag any action version that's outdated compared to upstream (just-bootstrap has explicit guidance about GitHub Actions versions).
   - `taiki-e/install-action@v2` is used for `just` installation (NOT the deprecated `extractions/setup-just`).

9. **Extend the generated Justfile** with custom recipes not provided by just-bootstrap:
   - `test-core` → `xcodebuild test -only-testing:GroundedCoreTests ...`
   - `test-adapters` → `xcodebuild test -only-testing:GroundedAdapterTests ...`
   - `test-integration` → `xcodebuild test -only-testing:GroundedIntegrationTests ...`
   - `inspect-state`, `inspect-poll`, `inspect-simulate`, `inspect-simulate-failure`, `inspect-history`, `inspect-clear-creds`, `inspect-classify`, `inspect-notify` — the curl+jq wrappers from the Inspect Surface section of `contract.md`
   - `icon` → runs `scripts/generate-icon.swift`
   - `dev` → launches the built app from `/tmp/grounded-build` so the debug server starts

10. **Configure signing** via keychain profile. Ted runs `xcrun notarytool store-credentials grounded-notarize --apple-id <email> --team-id <team> --password <app-specific-password>` once. Release workflow references the profile by name.

11. **Verify `just check` passes locally.** Includes core test, adapter test, integration test, linter, format check, build.

12. **Push and verify CI green.** Ensure `just check` in CI mirrors local.

13. **Commit Phase 1** as a small series of commits, each of which keeps `just check` green.

## Phase 1 verification

- [ ] `xcodegen generate` produces a buildable `.xcodeproj` that opens in **Xcode 26.4**
- [ ] Project compiles with Swift 6 strict concurrency, zero warnings
- [ ] `just check` passes locally and in CI (CI runner has Xcode 26.x)
- [ ] `just test-core` runs in <1s and uses Swift Testing (not XCTest)
- [ ] Running the built `.app` shows gray `bolt.car.circle` in the menubar with a 2-item menu
- [ ] `just inspect-state` against the running debug build returns valid JSON with `state: "unknown"`, `hasCredentials: false`
- [ ] `Sources/Core/` compiles with only `import Foundation` (verified by a CI script that greps for forbidden imports under `Sources/Core/**/*.swift`)
- [ ] `just icon` generates and updates AppIcon PNGs
- [ ] Pre-commit hook runs `just check`

## Phase 1 feedback loop

- **Playground:** running the built `.app` from `DerivedData` or `/tmp/grounded-build`
- **Inner-loop command:** `just build` (fast incremental Xcode build)
- **Experiment:** does the menubar icon appear; does clicking it show the menu; does Quit work; does `just inspect-state` return the expected JSON
