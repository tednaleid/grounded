# Phase 2: Core Features + First Release

**Parent contract:** [`contract.md`](./contract.md)
**Depends on:** [`phase-1-spec.md`](./phase-1-spec.md)

**Goal:** Fill in the hexagonal skeleton component by component, TDD-first. Ship 0.1.0.

## Build order

Strict dependency order — each step's tests must be red first, then green, before moving to the next.

### Core (pure, fast)

1. **`ChargerClassifier` + tests.** Parameterized tests over fixture snapshots covering every row of the 5-row classification table. Test matrix:
   - Idle, no session → `.healthyIdle`
   - Plugged, no session → `.healthyPluggedIn` ("Car plugged in")
   - Plugged, session state = `in_use` → `.activelyCharging`
   - Plugged, session state = `fully_charged` → `.healthyPluggedIn` ("Fully charged")
   - Offline (isConnected: false) → `.error("Charger offline")`
   Red: assertions against a stub that returns `.unknown`. Green: implement the 5-case classification.

2. **`RetryPolicy` + tests.** `shouldRetry(.networkFailure) == true`, `shouldRetry(.authFailure) == false`, `shouldRetry(.botBlocked) == false`, etc. Default delays `[2, 6]` exposed as a constant.

3. **`MonitorState` + tests.** Value semantics, equatability, helpers like `withFailure()`, `withSuccess(snapshot:at:)`. Pure struct math.

4. **`TransitionMessage` + tests.** Tests cover every legal transition pair and assert message content, including the error-entry message with "N failed checks over M minutes" and the recovery message. Also assert `.unknown → X` returns nil (no startup notification).

5. **`MonitoringTick` + tests.** This is the biggest test file. Matrix covers:
   - First tick from `.unknown` + success → visible state set, no transition notification
   - First tick from `.unknown` + transient failure → visible state stays `.unknown`, failure count = 1, no notification
   - First tick from `.unknown` + auth failure → immediate `.signedOut` + notification
   - From `.healthyIdle`, one transient failure → visible stays `.healthyIdle`, count = 1, no notification
   - From `.healthyIdle`, two transient failures → visible stays, count = 2, no notification
   - From `.healthyIdle`, three transient failures → visible transitions to `.error`, count = 3, notification fires
   - From `.error` with count 3, another transient failure → visible stays `.error`, count = 4, no duplicate notification
   - From `.error` with count 3, success → transition to classified state, count = 0, recovery notification fires
   - From `.healthyIdle` with count 1, success → visible stays, count = 0, no notification (reset silently)
   - From any state, auth failure → immediate `.signedOut`, fast-path bypasses threshold
   - Plug/unplug transitions when both ticks are successful → green → blue → green, each fires a notification

By this point the entire noise-suppressing notification-on-change behavior is proven correct by tests, with zero external dependencies.

### Ports

6. **Define protocols** for all seven ports in `Sources/Core/Ports/`. Compile-check only — no tests yet.

7. **Write the fakes** in `Tests/CoreTests/Fakes/`:
   - `InMemoryCredentialStore`
   - `QueuedChargerStatusSource`
   - `RecordingNotificationSink`
   - `ManualClock`
   - `RecordingStateObserver`

### Orchestrator

8. **`ChargerMonitor` + integration tests.** Wires fakes to ports. Test scenarios:
   - Happy path: idle → plugged → idle, each transition notifies (after baseline)
   - Flaky network: 1 failure then success → no notification, visible state unchanged
   - Real outage: 3 failures → error notification fires exactly once; 4th, 5th, 6th failure → no duplicate notifications
   - Recovery: 4 failures then success → recovery notification fires
   - Auth failure: healthy → 401 → signedOut notification immediately, threshold bypassed
   - Datadome: healthy → 403+captcha → signedOut notification immediately
   - Immediate launch poll: `ManualClock.advance(by: 0)` triggers first tick without waiting 10 min, and the result is silent
   - 10-minute cadence: `ManualClock.advance(by: 1800)` triggers exactly 3 poll ticks (not 4, not 2)
   - Credentials cleared mid-run: next tick → `.signedOut` via API client receiving 401

### Adapters (each TDD-first)

9. **`KeychainCredentialStore` + tests.** Round-trip save/load/clear under a test service name. Cleanup in `tearDown`.

10. **`ChargePointAPIClient` + tests.** Fixture-based. Use recorded JSON responses. Test:
    - Happy path for each endpoint (discovery, profile, chargers list, **charger status**, **user charging status**)
    - **Merged snapshot**: inject paired fixtures (`status_available_plugged.json` + `user_status_active.json`) → `fetchStatus()` returns a single `HomeChargerSnapshot` with `activeSession` populated
    - **Merged snapshot, no session**: pair `status_available_plugged.json` + `user_status_none.json` → snapshot with `activeSession == nil`
    - **Partial failure**: charger status succeeds, user charging status 500s → tick fails with `.serverError`, not a half-populated snapshot
    - Each error category mapping (401 → `.authFailure`, 403+captcha → `.botBlocked`, timeout → `.networkFailure`, malformed JSON → `.decodeFailure`, 500 → `.serverError`)
    - **In-tick retry behavior**: inject two `.networkFailure` then a success; total delay should match `[2, 6]` (ManualClock verifies), final result is the success snapshot
    - **Retry gives up**: three `.networkFailure` in a row — client returns `.networkFailure` to the caller after the configured retries are exhausted
    - **No retry on auth failure**: first call returns 401 → client returns `.authFailure` immediately, no retries attempted
    - Auth headers are set correctly (via `URLProtocol` mock)

11. **`UNCenterNotificationSink`.** Minimal test — just verify authorization-request surface and that `deliver` doesn't throw. Full coverage is manual because UNUserNotificationCenter is hard to mock.

12. **`SystemClock`.** Tests for `now()` and for schedule cancellation.

13. **`WKLoginBrowser`.** No automated test — inherently manual (real browser interaction). Repeatable verification path: `just inspect-clear-creds && just inspect-poll` to reach `.signedOut`, then click "Sign in..." in the menubar dropdown.

14. **`StatusItemController`.** Tests:
    - Given each ChargerState, the returned image has the expected tint (by inspecting `NSImage` properties)
    - Menu items are correct for each state, including sign in/out toggle
    - Menu shows "Last checked" and "Last successful check" timestamps formatted as relative strings using `RelativeDateTimeFormatter` (e.g., "2 minutes ago", "just now")
    - Menu rebuilds when `MonitorState` changes (observer pattern)

### Wire-up

15. **`AppDelegate.applicationDidFinishLaunching`** — construct the real adapter stack, wire to real `ChargerMonitor`, register observers, start `InspectServer` in DEBUG, trigger immediate silent baseline poll, then start the 10-minute schedule. Integration tests verify the wiring via `inspect-state` + `inspect-poll`.

16. **Debug `InspectServer` full implementation.** Expand from the Phase 1 minimal server to support all 8 endpoints, including `/simulate-failure`.

17. **Auto-launch integration.** Add "Open at Login" menu toggle using `SMAppService.mainApp.register() / unregister()`. Default enabled on first launch. Checkmark reflects `SMAppService.mainApp.status`.

### Release

18. **Hand-test every success criterion** using real credentials against Ted's real charger. Use the inspect recipes to force transitions and verify notifications fire — particularly `inspect-simulate-failure 3` to confirm the threshold machinery fires exactly one notification.

19. **`just bump 0.1.0`** — annotated tag, release notes via `claude -p`, push, workflow triggers, DMG built, signed, notarized, uploaded, cask updated in `tednaleid/homebrew-grounded`.

20. **Verify** `brew install --cask tednaleid/grounded/grounded` works from a clean state (a different machine or a fresh user).

## Phase 2 feedback loop

- **Playground:** the running debug `.app` launched via `just dev`
- **Inner loop command:** `just test-core` (subsecond) for core work, `just test-adapters` for adapter work, `just inspect-*` for integration verification
- **Parameterized experiments:**
  - `just inspect-classify status_available_unplugged.json` → expect `{"state": "healthyIdle"}`
  - `just inspect-classify status_offline.json` → expect `{"state": "error", "reason": "Charger offline"}`
  - `just inspect-simulate signedOut` → expect icon becomes gray + notification "Sign in to ChargePoint"
  - `just inspect-simulate healthyPluggedIn` → expect icon becomes blue + notification "Car plugged in"
  - `just inspect-simulate activelyCharging` → expect icon becomes electric yellow + notification "Charging started"
  - `just inspect-simulate-failure 1` → icon stays current color, no notification, `inspect-state` shows `consecutiveFailureCount: 1`
  - `just inspect-simulate-failure 1 && just inspect-simulate-failure 1` → still no notification, count = 2
  - `just inspect-simulate-failure 3` → icon turns red, exactly one notification fires with body mentioning "3 failed checks"
  - `just inspect-simulate-failure 3 && just inspect-poll` (where poll succeeds) → recovery notification fires, count = 0
  - `just inspect-clear-creds && just inspect-poll` → transition to signedOut + notification (not gated by threshold because 401 is non-transient)
  - `just inspect-notify "hello" "world"` → notification appears in upper right, labeled "grounded"
  - Plug real car in → within 10 min, `just inspect-history` shows a transition to `healthyPluggedIn` and notification is delivered
  - Unplug real car → within 10 min, transition to `healthyIdle`
  - Hold wifi off for 60 seconds mid-poll, then bring it back → no notification, visible state unchanged (in-tick retries absorb the blip)
  - Hold wifi off for 40 minutes → exactly one "Charger unreachable — 3 failed checks" notification, no duplicates
  - Click the menubar icon any time → menu shows "Last checked: Xm ago" and "Last successful check: Ym ago" with correct relative formatting
