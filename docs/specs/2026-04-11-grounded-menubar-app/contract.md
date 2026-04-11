# grounded — ChargePoint Home Charger Menubar App

**Type:** Signed macOS menubar app (Swift / AppKit + SwiftUI)
**Bundle ID:** `com.tednaleid.grounded`
**Toolchain:** Xcode **26.4** (build 17E192), Swift **6** language mode, Swift Testing for all new tests, strict concurrency enabled, deployment target **macOS 14.0**
**Infrastructure standard:** [just-bootstrap](file:///Users/tednaleid/.claude/plugins/cache/tednaleid/just-bootstrap/0.1.6/skills/just-bootstrap/SKILL.md) (Swift macOS app track)
**Reference apps:** `../limn`, `../montty` (XcodeGen + Justfile + notarytool + Homebrew cask + debug HTTP server for `just inspect-*`)

> **Status:** approved 2026-04-11. Phase 0 (materialize these specs into the repo) complete. Phases 1 and 2 execute from `phase-1-spec.md` and `phase-2-spec.md` in this directory.

---

## Context

The Python PoC at `check_charger.py` proved the ChargePoint API is reachable and can distinguish idle/charging/error from the `coulomb_sess` cookie. It's been committed and tested — exit 0, charger `13836601` found, state correctly classified as IDLE. But a `uv` script run manually isn't the end goal: Ted wants **passive, always-on monitoring** that notifies him when the charger changes state, because his menubar is set to autohide so a menubar icon alone isn't sufficient — the persistent **notification on state change** is the primary signal.

Goal: turn the PoC into a signed, distributable Swift menubar app named **grounded** that Ted can install once, sign in once through an embedded browser, and then trust to notify him whenever anything changes — especially errors. The same pipeline should be usable by anyone else via a Homebrew tap.

---

## Architecture Principles (non-negotiable)

Three principles govern everything below. Every file, test, and recipe exists to serve at least one of these.

### 1. Hexagonal (ports + adapters) with Swift 6 strict concurrency

Business logic lives in a pure **Core** module with zero framework dependencies — no AppKit, no UserNotifications, no URLSession, no WebKit, no Security.framework. Core can only `import Foundation`.

- **Core** — pure value types, pure functions, the state machine. Fast to test. No I/O. All types are `Sendable`.
- **Ports** — Swift protocols in Core that describe the shape of interactions with the outside world. All port methods are `async throws` (or `async` where no throwing makes sense). Protocols are `Sendable`.
- **Adapters** — concrete implementations of ports, each imports exactly the frameworks it needs. Adapters that touch shared mutable state are `actor` or `@MainActor`-isolated. No `DispatchQueue.main.async`, no completion handlers, no `@escaping` closures for async work — everything is structured concurrency via `Task`, `async let`, `TaskGroup`.
- **Composition root** — `AppDelegate.applicationDidFinishLaunching` is the only place where adapters are instantiated and wired to ports. Nothing else knows which adapter is in use.
- **`ChargerMonitor` is an `actor`** — it owns the mutable `MonitorState` and the polling `Task`. External callers interact with it only through async methods. This eliminates data races by construction under Swift 6 strict concurrency.
- **`StatusItemController` and `LoginWindowController` are `@MainActor`** — they touch AppKit which is main-thread-only.
- **Parallel API calls per tick** — `ChargePointAPIClient.fetchStatus()` uses `async let` to fetch `charger_status` and `user_charging_status` in parallel, then awaits both before merging into a single `HomeChargerSnapshot`. Cuts per-tick latency roughly in half.

Why: the charger classification state machine and the transition-notification dedup are pure functions of input. Proving them correct should not require a running app, a keychain, a network, or a clock. Ted's most important requirement — "know when the charger errors" — is implemented entirely inside the core, so a single fast test run gives confidence the app will do the right thing. Swift 6 strict concurrency closes the door on the class of bugs where "the state machine works in tests but races in production."

### 2. Red/green TDD — always — Swift Testing for new tests

All new tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — the framework Apple ships with Swift 6 and Xcode 26. No XCTest for code written as part of this project. Swift Testing gives us parameterized tests, better failure diagnostics, and matches the Swift 6 idioms we're using throughout.

For every component in the core and every adapter:

1. Write a failing `@Test` naming the behavior.
2. Run `just test-core` (or the adapter's scoped test recipe) and confirm it fails with the expected error.
3. Write the minimum code to make it pass.
4. Run again, confirm green.
5. Refactor if warranted.
6. Commit. Red/green pairs commit together — no "tests and impl in different commits that can't each pass check."

`just check` runs on every commit locally (pre-commit hook) and on every push (CI). A commit that breaks `just check` is a mistake to fix immediately, not to merge and clean up later.

### 3. Claude-drivable inspection surface

The app ships with a DEBUG-only localhost HTTP server (port TBD — pick something not 9876 to avoid collision with montty if both run) exposing endpoints that let Claude (or Ted, or a curl script) drive and introspect the running app without clicking menus or waiting 10 minutes for the next poll. Pattern is lifted directly from `../montty/Justfile:132-178` — each Justfile `inspect-*` recipe is a thin `curl ... | jq .` wrapper. No bespoke shell; the server does the work, recipes are one-liners.

The recipes below are the minimum set — each one must have a test that exercises it against a running debug build. See "Inspect Surface" section for the full list and their endpoints.

Why: grounded's observable surface in production is a tiny menubar icon and a notification. Debugging why the icon is the wrong color requires seeing everything the core sees, on demand, without restarting. Inspect recipes make the app transparent to Claude, which makes iteration dramatically faster — any test I run, the user can also run.

---

## Contract

### Problem Statement

Ted has a ChargePoint Home Flex charger (ID 13836601) that he relies on for overnight EV charging. ChargePoint has no public API and no notification mechanism for charging failures, so a failed charge is only discovered when Ted walks out to the car the next morning. The PoC proved the charger's state is queryable via the unofficial API, but manually running a script doesn't solve the problem — he needs **passive alerts when state changes**, delivered through macOS notifications, from a binary signed with his Developer ID so notifications are labeled "grounded" and the app can be installed like any other Mac app (and eventually shared).

### Goals

1. Deliver a signed macOS menubar app that polls the ChargePoint API every 10 minutes, shows a coloured `bolt.car.circle` in the menubar, and displays the last successful check time when the icon is clicked.
2. Fire a persistent macOS notification (labeled "grounded") whenever the charger transitions between the five classified visible states — **but not on transient single-tick failures**. Only alert when a problem persists long enough to be real, to avoid waking Ted at 2am for a 30-second wifi hiccup.
3. Tolerate transient network and server errors via a two-layer resilience strategy: in-tick URLSession retries with short backoff, plus a consecutive-failure threshold before the visible state transitions to `.error`.
4. Store the ChargePoint session cookie securely in Keychain after a one-time WKWebView login flow, so first-launch UX is "click 'Sign in', log in, done" with no hand-copied cookies.
5. Adopt the full just-bootstrap standard (Justfile, CI, release, Homebrew cask, bump/retag) so the app is installable via a dedicated `tednaleid/homebrew-grounded` tap and releasable via `just bump <version>`.
6. Separate pure business logic from framework-coupled adapters using hexagonal architecture, so classification, transition logic, retry policy, and failure-threshold behavior are fully unit-testable without a running app.
7. Expose a debug HTTP server + `just inspect-*` recipes that let Claude drive and introspect the app during development without manual UI interaction or waiting 10 minutes for the next poll.

### Success Criteria

- [ ] `brew install --cask tednaleid/grounded/grounded` (dedicated tap `tednaleid/homebrew-grounded`) installs the app after the tap is bootstrapped
- [ ] First launch with no credentials shows a WKWebView login window pointed at driver.chargepoint.com
- [ ] Completing that login closes the window and transitions the menubar icon out of the "signed out" state
- [ ] Menubar icon shows `bolt.car.circle` tinted green/blue/yellow/red/gray matching the classification table below
- [ ] Clicking the menubar icon shows a dropdown with: status label, **last checked (relative)**, **last successful check (relative)**, Sign in/out, Open ChargePoint, Open at Login toggle, Quit
- [ ] When the charger state transitions to a new classified state, a notification appears with title "grounded" and body describing the transition
- [ ] **A single transport failure (5xx, timeout, DNS, decode) does NOT fire a notification and does NOT change the visible icon color** — the previous known-good state is preserved
- [ ] **A single successful HTTP response where the payload reports `isConnected: false` DOES fire a notification on the first sighting** and transitions the icon to red — the charger is telling us clearly, we trust it
- [ ] After **three consecutive transport failures** (~30 minutes of real failure), the icon transitions to red and one notification fires describing how long it's been failing
- [ ] When the charger recovers after a transport-failure-induced error, one recovery notification fires and the icon returns to green/blue
- [ ] When the charger recovers from a payload-reported error (`isConnected` flips back to `true`), the next successful poll fires a recovery notification — no threshold involved
- [ ] Authentication failures (401/Datadome) transition to `.signedOut` immediately without waiting for the failure threshold, because retrying with a bad token is pointless
- [ ] Notifications are attributed to "grounded", not "Script Editor" or "terminal-notifier"
- [ ] Quitting and relaunching preserves the session — no re-login needed
- [ ] First poll after launch runs immediately (not after 10 minutes), silently, to establish baseline state
- [ ] After a full machine restart, the app auto-launches via `SMAppService.mainApp.register()` and resumes monitoring without prompting for credentials
- [ ] `just check` passes locally (pre-commit hook) and in CI on every push
- [ ] `just test-core` runs in under 1 second and covers: every row of the classification table, every transition edge, the failure-threshold state machine (1/2/3/4 consecutive failures + recovery), retry policy math, and auth-failure fast-path — all with zero external dependencies
- [ ] `just bump 0.1.0` creates an annotated tag, generates release notes, triggers the release workflow, and publishes a DMG + updates the Homebrew cask
- [ ] Every `just inspect-*` recipe has at least one test that hits the debug endpoint it wraps and asserts the response shape
- [ ] The entire `Sources/Core/` directory compiles with only `import Foundation` — no AppKit, no Security, no URLSession, no WebKit, no UserNotifications, no XCTest

### Scope

**In scope (MVP):**

- Hexagonal split: `Sources/Core/`, `Sources/Ports/`, `Sources/Adapters/*/`, `Sources/App/`
- Single-charger monitoring (use the first ID returned by `get_home_chargers`)
- Five classified visible states (SignedOut, HealthyIdle, HealthyPluggedIn, ActivelyCharging, Error)
- Each poll fetches BOTH `home_charger_status` and `user_charging_status` and merges them into one `HomeChargerSnapshot`; both must succeed for a tick to be a transport success
- WKWebView login flow with cookie harvesting from `WKWebsiteDataStore`
- Keychain storage for `coulomb_sess` + email + cached region + userId + chargerId
- **10-minute polling interval** (constant in `MonitoringConfig`; tests use a `ManualClock` to drive time)
- **First poll runs immediately on launch**, silent (establishes baseline)
- **In-tick retry policy**: network/server errors retry twice with delays [2s, 6s] before the tick is marked failed; auth failures are NOT retried
- **Failure threshold**: visible state does not transition to `.error` until **3 consecutive ticks fail**. Below threshold, icon keeps showing last known good state and no notification fires
- **Recovery notification**: when a tick succeeds after >=3 consecutive failures, one recovery notification fires
- Menubar dropdown menu includes status label + "Last checked: Xm ago" + "Last successful check: Ym ago"
- State-change notifications via `UNUserNotificationCenter`
- `SMAppService.mainApp` auto-launch, default enabled, toggleable from menu
- Debug HTTP server + `just inspect-*` recipes (DEBUG builds only)
- Pure Core tests with fakes for every port
- just-bootstrap infrastructure (Justfile, CI, release workflow, Homebrew cask, pre-commit hook)
- Developer ID signing + notarization via keychain profile `grounded-notarize`
- Ship 0.1.0 tag triggering a release with a DMG and cask update to `tednaleid/homebrew-grounded`

**Out of scope:**

- Multiple chargers (pick first, ignore rest — note in logs if >1 found)
- User-configurable polling interval or quiet hours
- Historical charts, session logs, or billing data
- Anomaly detection ("I expected a charge overnight and didn't get one") — requires persistent state + schedule modeling, separate project
- Sparkle/auto-updates — rely on Homebrew for updates
- Password auth / token paste UI — WKWebView is the only login path
- Fetching the full `ChargingSession` details (power_kw, miles_added, energy_kwh) — MVP only needs "session exists and is not `fully_charged`" to decide ActivelyCharging. Session details are deferred.

**Future considerations:**

- Anomaly detection with scheduled expectations
- Per-state notification preferences
- Detailed session history view (power_kw, energy_kwh, miles_added) — would require fetching the full ChargingSession
- Multi-charger support
- App icon refinement beyond the rendered `bolt.car.circle`
- Tunable electric yellow shade based on how it reads in real menubar

---

## State Classification

All five states use the same SF Symbol — **`bolt.car.circle`** (not `.fill`) — recolored per state. Same symbol across states keeps the menubar visually stable and semantically communicates "EV charger" at a glance.

| State | Condition | SF Symbol | Tint | Notification body on entry |
|---|---|---|---|---|
| `SignedOut` | No credentials in Keychain, OR last API call returned 401/InvalidSession/DatadomeCaptcha | `bolt.car.circle` | secondaryLabel (gray) | "Sign in to ChargePoint" — tapping opens the login window |
| `HealthyIdle` | `isConnected == true` AND `isPluggedIn == false` | `bolt.car.circle` | systemGreen | "Charger idle" |
| `HealthyPluggedIn` | `isConnected == true` AND `isPluggedIn == true` AND **(no active session OR session `state == "fully_charged"`)** | `bolt.car.circle` | systemBlue | First plug-in: "Car plugged in". Post-charge: "Fully charged" |
| `ActivelyCharging` | `isConnected == true` AND `isPluggedIn == true` AND active session exists AND session `state != "fully_charged"` | `bolt.car.circle` | electric yellow (`NSColor(red: 1.0, green: 0.95, blue: 0.1, alpha: 1.0)` — starting point, tunable) | "Charging started" |
| `Error` | `isConnected == false` OR transport-failure threshold crossed OR unmapped `chargingStatus` value | `bolt.car.circle` | systemRed | `"Charger offline"` / `"API error: <short>"` / `"Unknown state: <raw>"` |

**Normal overnight flow** produces four notifications in sequence: blue "Car plugged in" → yellow "Charging started" → blue "Fully charged" → green "Charger idle" (after unplugging the next morning). Each color signals a different real-world meaning and fires exactly once per transition.

**Notification semantics with failure threshold:**

**Critical distinction — "transport failure" vs "successful response reporting a problem":**

- A **transport failure** means the HTTP request itself didn't land: 5xx, network timeout, DNS, TLS error, malformed JSON body. `ChargePointAPIClient.fetchStatus()` returns `.failure(.networkFailure | .serverError | .decodeFailure | .botBlocked | .authFailure)`. We don't know what the charger is doing. These go through the in-tick retry loop and the 3-tick threshold.
- A **successful response reporting a problem** means HTTP 200 with a valid JSON body where the *payload* says something is wrong — most importantly `isConnected: false`, and in the future possibly `chargingStatus: "FAULTED"` or similar. `fetchStatus()` returns `.success(snapshot)` — the request worked perfectly. The `ChargerClassifier` then maps the snapshot to `.error("Charger offline")`. **This path is trusted on the first sighting: transition and notify immediately, `consecutiveFailureCount` stays 0.** The charger is telling us clearly what state it's in — we don't second-guess it.

Concretely: if `fetchStatus()` returns `.success(HomeChargerSnapshot(isConnected: false, ...))`, the monitor transitions straight to `.error` and notifies on that first poll. The threshold **only gates** the `.failure(...)` arm of the Result.

**Per-tick behavior:**

- The monitor starts in `.unknown` (no icon, no notification).
- On launch, an immediate silent poll establishes the baseline visible state.
- On every subsequent 10-minute tick:
  - **Successful HTTP response:** reset `consecutiveFailures = 0`, update `lastSuccessAt` and `lastSuccessfulSnapshot`, run `ChargerClassifier.classify(snapshot)` to derive the visible state. If the classified state differs from the current visible state, fire a notification and update the icon. **This includes classifier-produced `.error` states — those are real and trusted.**
  - **Transport failure (transient — network/server/decode):** increment `consecutiveFailures`. If it's now **< 3**, the visible state and icon stay unchanged (last known good), no notification. If it's **== 3**, transition visible state to `.error` and fire ONE notification: "Charger unreachable — 3 failed checks". If it's **> 3**, stay in `.error`, no duplicate notification.
  - **Transport failure (non-transient — auth/Datadome):** bypass the threshold entirely. Transition to `.signedOut` immediately and notify ("Sign in to ChargePoint"). Retrying is pointless.
  - **Recovery after a transport-failure-induced error:** first successful HTTP response after a 3+-failure streak fires a "Charger reachable again" notification and transitions the visible state based on the new snapshot.
- App relaunches reset `.unknown` + `consecutiveFailures = 0`. The immediate launch poll is silent regardless of outcome, so a relaunch doesn't trigger spurious notifications.

The classification table above describes what the icon looks like for a given **visible state**. The mapping from (previous visible state, tick result, consecutive failure count) to (new visible state, maybe transition) lives in `MonitoringTick` in Core and is tested exhaustively.

**Mapping from API fields to the 5 visible states** (this is `ChargerClassifier.classify(snapshot:)` in Core):

```
isConnected == false                                        → .error("Charger offline")
isConnected && !isPluggedIn                                 → .healthyIdle
isConnected && isPluggedIn && activeSession == nil          → .healthyPluggedIn
isConnected && isPluggedIn && activeSession.state == "fully_charged"
                                                            → .healthyPluggedIn
isConnected && isPluggedIn && activeSession.state != "fully_charged"
                                                            → .activelyCharging
```

`SignedOut` is produced by `MonitoringTick`, not the classifier — it comes from auth-failure fast-path, not from a successful snapshot.

---

## Hexagonal Architecture — Detailed

### Core (`Sources/Core/`)

Pure Swift. Imports only `Foundation`. No frameworks, no I/O. Every type here is testable in milliseconds.

| Type | Responsibility |
|---|---|
| `ChargerState` enum | `.unknown`, `.signedOut`, `.healthyIdle`, `.healthyPluggedIn`, `.activelyCharging`, `.error(String)`. `Equatable`. Describes what the icon shows. |
| `HomeChargerSnapshot` | Pure value type merging both API calls: `chargerId`, `isConnected`, `isPluggedIn`, `chargingStatus`, `activeSession: ActiveSessionInfo?`. The `activeSession` field is nil when no session is in progress. |
| `ActiveSessionInfo` | Pure value type: `sessionId: Int`, `state: String` (e.g. `"in_use"`, `"fully_charged"`). Extracted from `user_charging_status` response. |
| `APIErrorCategory` enum | `.authFailure`, `.networkFailure`, `.serverError(message: String)`, `.decodeFailure`, `.botBlocked`. Simplified view of errors for the classifier. Includes `isTransient: Bool` — true for `.networkFailure`/`.serverError`/`.decodeFailure`, false for `.authFailure`/`.botBlocked`. Only transient failures count toward the failure threshold; non-transient ones transition immediately. |
| `MonitorState` | The full core state: `visibleState: ChargerState`, `lastSuccessfulSnapshot: HomeChargerSnapshot?`, `lastSuccessAt: Date?`, `lastAttemptAt: Date?`, `lastAttemptOutcome: Result<HomeChargerSnapshot, APIErrorCategory>?`, `consecutiveFailureCount: Int`. Pure value type. Every monitor transition produces a new `MonitorState`. |
| `MonitoringConfig` | `pollInterval: TimeInterval = 600` (10 min), `failureThreshold: Int = 3`, `inTickRetryDelays: [TimeInterval] = [2, 6]`. All tunable; defaults match the Goals. |
| `RetryPolicy` | Pure struct with `delays: [TimeInterval]` plus `shouldRetry(_ error: APIErrorCategory) -> Bool` (returns false for non-transient). Adapters consult this to decide in-tick retries. Pure math, no time or IO — the mechanism (actually sleeping) lives in the adapter using a `Clock` port. |
| `ChargerClassifier` | Pure static function `classify(_ snapshot: HomeChargerSnapshot) -> ChargerState` — maps a successful snapshot to one of `.healthyIdle`, `.healthyPluggedIn`, `.activelyCharging`, or `.error(...)`. Does not produce `.signedOut` (auth failures are handled by `MonitoringTick`, not the classifier). |
| `StateTransition` | `struct { from: ChargerState; to: ChargerState }`. |
| `TransitionMessage` | Pure function `message(for: StateTransition, context: MonitorState) -> (title: String, body: String)?`. Returns nil for startup (`.unknown → anything`). For error entry, body reads "Charger unreachable — 3 failed checks over 30 minutes" using `context.consecutiveFailureCount` and `context.lastSuccessAt`. For recovery, "Charger reachable again". |
| `MonitoringTick` | Pure function `tick(previous: MonitorState, result: Result<HomeChargerSnapshot, APIErrorCategory>, at: Date, config: MonitoringConfig) -> TickOutcome` where `TickOutcome` is `{ newState: MonitorState, transition: StateTransition? }`. This is the heart of the state machine. Encapsulates: threshold-gating for transient failures, fast-path for non-transient failures, recovery detection, classification of successful snapshots. Zero framework deps; trivially tested with a matrix of (previous, result, time) inputs. |

### Ports (`Sources/Core/Ports/`, still pure Foundation)

Swift protocols defining the shape of external interactions. Adapters implement these.

All ports are `Sendable` protocols with `async throws` methods so they compose cleanly across actors under Swift 6 strict concurrency.

| Port | Responsibility |
|---|---|
| `ChargerStatusSource` | `func fetchStatus() async throws -> HomeChargerSnapshot`. Throws `APIErrorCategory`. Adapter maps HTTP errors, timeouts, decode failures. Uses `async let` internally to parallelize the 2 required API calls. |
| `CredentialStore` | `var hasCredentials: Bool { get async }`, `func load() async throws -> Credentials?`, `func save(_ creds: Credentials) async throws`, `func clear() async throws`. `Credentials` is a `Sendable` struct (email, token, region, userId, chargerId). |
| `NotificationSink` | `func requestAuthorization() async -> Bool`, `func deliver(title: String, body: String) async`. |
| `BrowserAuth` | `@MainActor func presentLogin() async throws -> HarvestedSession`. Main-actor-isolated because it presents a window. |
| `Clock` | `func now() -> Date`, `func sleep(for: Duration) async throws`. Tests use a fake clock where `sleep` returns immediately and the test drives time via `advance(by:)`. Production uses `ContinuousClock`. |
| `StateObserver` | `func stateDidChange(_ state: MonitorState) async`. `StatusItemController` implements this to repaint the icon; `NotificationPresenter` implements it to fire notifications. Multiple observers allowed. |
| `InspectSink` (DEBUG only) | `func currentSnapshot() async -> InspectSnapshot` — returns a JSON-serializable view of current state for the debug server. |

### Adapters (`Sources/Adapters/<name>/`)

One directory per adapter. Each imports exactly the frameworks it needs. No adapter imports another adapter.

| Adapter | Implements | Imports |
|---|---|---|
| `ChargePointAPI/ChargePointAPIClient.swift` | `ChargerStatusSource` | `Foundation` (URLSession). Also contains `APIModels.swift` (private Codable structs — not exported to Core), `APIError.swift` (maps URLSession/HTTP errors to `APIErrorCategory`). |
| `Keychain/KeychainCredentialStore.swift` | `CredentialStore` | `Security` |
| `Notifications/UNCenterNotificationSink.swift` | `NotificationSink` | `UserNotifications` |
| `WebKit/WKLoginBrowser.swift` | `BrowserAuth` | `WebKit`, `AppKit` (for the hosting window) |
| `System/SystemClock.swift` | `Clock` | `Foundation` (Timer / DispatchQueue / Task.sleep) |
| `AppKit/StatusItemController.swift` | `StateObserver` | `AppKit` |
| `Debug/InspectServer.swift` (DEBUG only) | (sidecar, not a port) | `Network` (NWListener) or `Foundation` URLSession server |

### Composition root (`Sources/App/`)

| File | Responsibility |
|---|---|
| `GroundedApp.swift` | `@main` SwiftUI `App` with `NSApplicationDelegateAdaptor(AppDelegate.self)` and a `Settings {}` scene (no visible window). |
| `AppDelegate.swift` | `@MainActor`. In `applicationDidFinishLaunching`: instantiate every adapter, inject into `ChargerMonitor`, register observers, start the debug server if `#if DEBUG`, launch the monitor's poll task. Presents the login window if no credentials. |
| `ChargerMonitor.swift` | **`actor`**. Lives in `App/`, not `Core/`, because it orchestrates ports and the clock. Pure state transitions live in `Core/MonitoringTick`; `ChargerMonitor` is a thin coordinator that holds the current `MonitorState`, calls `MonitoringTick.tick` on each poll, updates observers. The polling loop is a `Task` that `await clock.sleep(for: .seconds(600))` between ticks. Task cancellation on app shutdown is structured. |

### Tests (`Tests/`)

Three test targets, three speeds, enforced by separate Justfile recipes.

| Target | Location | What it tests | Speed target |
|---|---|---|---|
| `GroundedCoreTests` | `Tests/CoreTests/` | Core types and functions — classifier, transition detector, MonitoringTick. Uses fakes for every port. | `just test-core` runs in <1s |
| `GroundedAdapterTests` | `Tests/AdapterTests/` | Each adapter in isolation — KeychainCredentialStore round-trip against a test keychain, ChargePointAPIClient against recorded fixtures, UNCenterNotificationSink authorization request. | `just test-adapters` runs in <10s |
| `GroundedIntegrationTests` | `Tests/IntegrationTests/` | ChargerMonitor wired to fake adapters, simulating full app behavior over a `ManualClock` timeline. Also: inspect server endpoint smoke tests. | `just test-integration` runs in <5s |

**Fakes** (in `Tests/CoreTests/Fakes/`, reused across targets):

- `InMemoryCredentialStore` — tests pre-populate and inspect
- `QueuedChargerStatusSource` — tests enqueue a sequence of `Result<HomeChargerSnapshot, APIErrorCategory>`; each `fetchStatus()` call dequeues one
- `RecordingNotificationSink` — captures every `deliver(title:body:)` call for assertions
- `ManualClock` — tests call `advance(by:)` to trigger scheduled work; no real `sleep`
- `RecordingStateObserver` — captures every `stateDidChange` call

**Fixtures** (`Tests/Fixtures/chargepoint/`): recorded, scrubbed JSON responses from real API calls. One fixture per row of the classification table plus error cases. See the Repository Layout section for the full file list.

---

## Repository Layout (target after Phase 1)

```
grounded/
├── .github/workflows/
│   ├── ci.yml                          # generated by just-bootstrap, runs `just check`
│   └── release.yml                     # generated by just-bootstrap, tag-triggered
├── .gitignore                          # + /tmp/grounded-build, .DS_Store, xcuserdata
├── CLAUDE.md                           # generated; notes TDD workflow, just check, inspect recipes
├── docs/specs/
│   └── 2026-04-11-grounded-menubar-app/
│       ├── contract.md                 # this file
│       ├── phase-1-spec.md
│       └── phase-2-spec.md
├── Justfile                            # generated + custom inspect-* recipes
├── project.yml                         # XcodeGen config
├── README.md
├── Resources/
│   ├── Info.plist                      # LSUIElement=true, version 0.0.1 pre-release
│   ├── grounded.entitlements           # unsandboxed + hardened runtime
│   └── Assets.xcassets/AppIcon...      # green bolt.car.circle rendered PNGs
├── scripts/
│   ├── generate-icon.swift             # render bolt.car.circle to AppIcon sizes
│   └── setup-homebrew-tap.sh           # generated by just-bootstrap
├── Sources/
│   ├── App/
│   │   ├── GroundedApp.swift           # @main
│   │   ├── AppDelegate.swift           # composition root
│   │   └── ChargerMonitor.swift        # orchestrator, uses Core + Ports
│   ├── Core/
│   │   ├── ChargerState.swift
│   │   ├── HomeChargerSnapshot.swift
│   │   ├── APIErrorCategory.swift
│   │   ├── MonitorState.swift
│   │   ├── MonitoringConfig.swift
│   │   ├── RetryPolicy.swift
│   │   ├── ChargerClassifier.swift
│   │   ├── StateTransition.swift
│   │   ├── TransitionMessage.swift
│   │   ├── MonitoringTick.swift
│   │   └── Ports/
│   │       ├── ChargerStatusSource.swift
│   │       ├── CredentialStore.swift
│   │       ├── NotificationSink.swift
│   │       ├── BrowserAuth.swift
│   │       ├── Clock.swift
│   │       ├── StateObserver.swift
│   │       └── InspectSink.swift       # DEBUG only via #if
│   └── Adapters/
│       ├── ChargePointAPI/
│       │   ├── ChargePointAPIClient.swift
│       │   ├── APIModels.swift         # internal Codable structs
│       │   └── APIErrorMapping.swift
│       ├── Keychain/
│       │   └── KeychainCredentialStore.swift
│       ├── Notifications/
│       │   └── UNCenterNotificationSink.swift
│       ├── WebKit/
│       │   └── WKLoginBrowser.swift
│       ├── System/
│       │   └── SystemClock.swift
│       ├── AppKit/
│       │   └── StatusItemController.swift
│       └── Debug/
│           └── InspectServer.swift     # #if DEBUG
└── Tests/
    ├── CoreTests/
    │   ├── ChargerClassifierTests.swift
    │   ├── TransitionMessageTests.swift
    │   ├── MonitoringTickTests.swift
    │   ├── RetryPolicyTests.swift
    │   ├── MonitorStateTests.swift
    │   └── Fakes/
    │       ├── InMemoryCredentialStore.swift
    │       ├── QueuedChargerStatusSource.swift
    │       ├── RecordingNotificationSink.swift
    │       ├── ManualClock.swift
    │       └── RecordingStateObserver.swift
    ├── AdapterTests/
    │   ├── KeychainCredentialStoreTests.swift
    │   ├── ChargePointAPIClientTests.swift    # against fixtures
    │   └── UNCenterNotificationSinkTests.swift
    ├── IntegrationTests/
    │   ├── ChargerMonitorTests.swift          # end-to-end over ManualClock
    │   └── InspectServerTests.swift           # hit debug endpoints, assert shape
    └── Fixtures/chargepoint/
        ├── status_available_unplugged.json           # HomeChargerStatus, idle
        ├── status_available_plugged.json             # HomeChargerStatus, plugged but no session
        ├── status_offline.json                       # HomeChargerStatus with isConnected: false
        ├── user_status_none.json                     # user_charging_status response when nothing is charging
        ├── user_status_active.json                   # user_charging_status with an in-progress session
        ├── user_status_fully_charged.json            # user_charging_status with state: "fully_charged"
        ├── error_401.json
        └── error_datadome.json
```

**Deleted from current repo (Phase 1):** `check_charger.py`, `.env`, `.env.example`. Git history preserves the PoC. `.llm/python-chargepoint/` stays (read-only reference).

---

## ChargePoint API Re-implementation (adapter)

The `ChargePointAPIClient` adapter re-implements only the endpoints the MVP needs. The Python library at `.llm/python-chargepoint/` stays as read-only reference — we do not depend on it.

**Endpoints** (from `.llm/python-chargepoint/python_chargepoint/client.py`):

| Call | Frequency | Method + URL template | Python reference |
|---|---|---|---|
| Discovery | once on first login, cached | `POST {DISCOVERY_API}` body `{"username": email}` → GlobalConfiguration | `client.py:261-275` |
| Profile | once on first login, cached | `GET {accounts_endpoint}/v1/driver/profile/user` → `Account` (for `userId`) | `client.py:277-286` |
| Home chargers | once on first login, cached | `GET {hcpo_hcm_endpoint}/api/v1/configuration/users/{userId}/chargers` → `[{id: Int}]` (for `chargerId`) | `client.py:301-317` |
| **Charger status** | **every tick** | `GET {hcpo_hcm_endpoint}/api/v1/configuration/users/{userId}/chargers/{chargerId}/status` → `HomeChargerStatus` | `client.py:320-331` |
| **User charging status** | **every tick** | `POST {mapcache_endpoint}/v2` body `{"user_status": {"mfhs": {}}}` → `UserChargingStatus?` (nil when no session) | `client.py:348-362` |

Per-poll cost: 2 HTTP calls (charger status + user charging status), merged into one `HomeChargerSnapshot` inside `ChargePointAPIClient.fetchStatus()`. Both must succeed, or the tick is a transport failure. The three setup calls (discovery, profile, home chargers) run once after login, cached in Keychain alongside the token.

`DISCOVERY_API` constant: read from `.llm/python-chargepoint/python_chargepoint/constants.py` during Phase 2.

**Required headers on authenticated calls** (`client.py:186-192`):
```
cp-session-type: CP_SESSION_TOKEN
cp-session-token: <coulomb_sess value>
cp-region: <region from discovery>
user-agent: grounded/<version>
```
Plus the `coulomb_sess` cookie must be in the URLSession's `HTTPCookieStorage`.

**JSON → Core mapping:** the adapter decodes into private Codable structs, then projects to `HomeChargerSnapshot`. This decoupling means adding fields to the API response or renaming things in the raw JSON has zero impact on Core.

**Error mapping** (`APIErrorMapping.swift`):

| Input | Output | Transient? |
|---|---|---|
| HTTP 401 | `.authFailure` | no — fast-path to `.signedOut` |
| HTTP 403 with Datadome captcha body | `.botBlocked` | no — fast-path to `.signedOut` |
| URLSession network error (timeout, unreachable host, DNS) | `.networkFailure` | yes — in-tick retry, then count toward threshold |
| Decode error | `.decodeFailure` | yes |
| Any other non-200 | `.serverError(message: statusLine)` | yes |

**In-tick retry loop** lives inside `ChargePointAPIClient.fetchStatus()`. On a transient error, the client consults `RetryPolicy` (injected, from Core) and sleeps via an injected `Clock` before retrying. Default delays `[2s, 6s]` → up to 3 total attempts per tick before the tick is reported as failed to `ChargerMonitor`. Non-transient errors skip the retry loop entirely.

This means: the `ChargerStatusSource` port contract is "fetchStatus() may take up to ~10 seconds; internal retries are an implementation detail; return success or map the final error to `APIErrorCategory`." The Core sees only success-or-failure per tick, and the 3-tick failure threshold multiplies that, so the worst-case time from "charger goes offline" to "user notified" is roughly `3 × 10min + 3 × 8s ≈ 30.4 minutes`. Fast enough for an overnight-charging use case, slow enough to tolerate transient blips.

---

## Inspect Surface

Debug HTTP server listens on `localhost:<PORT>` in DEBUG builds only (pick a port that doesn't collide with montty's 9876 — 9877 is fine unless something else claims it). Endpoints return JSON. Justfile wrappers are curl+jq one-liners matching montty's pattern.

### Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/state` | GET | Full `MonitorState`: visibleState, lastSuccessfulSnapshot, lastSuccessAt, lastAttemptAt, lastAttemptOutcome, consecutiveFailureCount, hasCredentials |
| `/force-poll` | POST | Bypass the 10-min timer, trigger one immediate fetch + classify, return the resulting `MonitorState` |
| `/simulate` | POST body `{"state": "error", "reason": "test"}` | Inject a synthetic state transition (for testing notification delivery and icon updates) |
| `/simulate-failure` | POST body `{"category": "networkFailure", "count": 3}` | Inject N consecutive transient failures in a row (drives the failure-threshold machinery without real network) |
| `/history` | GET | Last N state transitions from an in-memory ring buffer, with timestamps |
| `/clear-credentials` | POST | Delete keychain entry; next tick will see `.signedOut` via auth-failure fast-path |
| `/classify` | POST body `<JSON fixture>` | Run the core classifier on an arbitrary snapshot JSON, return the resulting state without touching real state |
| `/notify-test` | POST body `{"title": "...", "body": "..."}` | Deliver a test notification via the real NotificationSink |

### Justfile recipes

```
just inspect-state                       → curl /state | jq .
just inspect-poll                        → curl -X POST /force-poll | jq .
just inspect-simulate STATE              → curl -X POST /simulate -d '{"state":"STATE"}' | jq .
just inspect-simulate-failure COUNT      → curl -X POST /simulate-failure -d '{"category":"networkFailure","count":COUNT}' | jq .
just inspect-history                     → curl /history | jq .
just inspect-clear-creds                 → curl -X POST /clear-credentials
just inspect-classify FIXTURE            → curl -X POST /classify -d @FIXTURE | jq .
just inspect-notify TITLE BODY           → curl -X POST /notify-test -d ...
```

Each recipe gets one integration test in `Tests/IntegrationTests/InspectServerTests.swift` that boots the server with a fake adapter stack, hits the endpoint, and asserts the response shape.

---

## Decisions Locked In

| Decision | Chosen |
|---|---|
| Xcode | **26.4** (build 17E192) — current as of this contract |
| Swift | **6** language mode, strict concurrency enabled (`complete`) |
| Deployment target | macOS 14.0 (Sonoma) |
| UI framework | AppKit (NSStatusItem, NSMenu, NSWindow, WKWebView hosting) + SwiftUI App scene for `@main` |
| Test framework | **Swift Testing** (`@Test`, `#expect`) — not XCTest |
| Concurrency model | Swift Concurrency end-to-end: `actor` for `ChargerMonitor`, `@MainActor` for UI controllers, `async let` for parallel API calls, structured `Task` for the polling loop, no `DispatchQueue`, no completion handlers |
| Architecture | Hexagonal (ports + adapters); Core is pure Foundation; all types `Sendable` |
| Test discipline | TDD red/green; `just check` enforced by pre-commit hook and CI |
| Inspection | Debug-only HTTP server + `just inspect-*` curl wrappers (montty pattern) |
| Login UX | WKWebView → harvest `coulomb_sess` from WKWebsiteDataStore → Keychain |
| Menubar icon | `bolt.car.circle` (not `.fill`), recolored per state |
| **Visible states** | **5: SignedOut (gray), HealthyIdle (green), HealthyPluggedIn (blue), ActivelyCharging (electric yellow), Error (red)** |
| **Electric yellow starting color** | `NSColor(red: 1.0, green: 0.95, blue: 0.1, alpha: 1.0)` — tunable after seeing it in real menubar |
| **Per-tick API calls** | 2 (`charger_status` + `user_charging_status`), merged into one snapshot |
| Menubar menu | Status label + "Last checked" + "Last successful check" + Sign in/out + Open ChargePoint + Open at Login toggle + Quit |
| App bundle icon | Green `bolt.car.circle` rendered at all AppIcon sizes via `scripts/generate-icon.swift` |
| Auto-launch | `SMAppService.mainApp.register()`, surfaced as toggleable "Open at Login" menu item, default enabled |
| **Poll interval** | **10 minutes (600s)**, constant in `MonitoringConfig` |
| **Failure threshold** | **3 consecutive failed ticks** before transitioning to `.error` and notifying |
| **In-tick retry delays** | **`[2s, 6s]`** — up to 3 attempts per tick for transient errors |
| **Auth failure behavior** | Bypass threshold, immediate `.signedOut` + notification |
| **First-launch poll** | Immediate + silent (baseline), then 10-min cadence |
| Homebrew tap | Dedicated: `tednaleid/homebrew-grounded` |
| Starting release version | `0.1.0` (first real release after Phase 2) |
| Infrastructure generator | `/just-bootstrap` (Swift macOS app track) |
| PoC files | Deleted in Phase 1 |

---

## Verification (Phase 2 sign-off)

- [ ] All Success Criteria above pass
- [ ] With Notification Center style set to "Alerts" for grounded in System Settings → Notifications, a state-change notification persists in the upper-right until dismissed (Dropbox-style)
- [ ] `just test-core` runs in <1s
- [ ] `just test-adapters` runs in <10s
- [ ] `just test-integration` runs in <5s
- [ ] `just check` stable green on CI for 5 consecutive pushes
- [ ] Inspect recipe coverage: every `inspect-*` recipe has at least one test in `Tests/IntegrationTests/InspectServerTests.swift`
- [ ] Core purity enforced: a CI step greps for forbidden imports (`AppKit|UIKit|WebKit|Security|UserNotifications|URLSession`) under `Sources/Core/` and fails if any match

---

## Execution Plan

### Dependency graph

```
Phase 0: Materialize docs/specs/                       (done — this commit)
    └── Phase 1: Scaffold + just-bootstrap + inspect   (blocked by Phase 0)
        └── Phase 2: TDD core → ports → adapters →
                     wire-up → release 0.1.0           (blocked by Phase 1)
```

### Strategy: sequential

No parallelism at this granularity. Within Phase 2 the build order (core → ports → fakes → orchestrator → adapters → wire-up → release) is itself a dependency chain.

### Execution steps

1. **Phase 0** — materialize `docs/specs/2026-04-11-grounded-menubar-app/` from the approved plan. Commit. **Complete.**
2. **Phase 1** — execute `phase-1-spec.md`, invoke `/just-bootstrap`, verify `just check` green in CI. Commit.
3. **Phase 2** — execute `phase-2-spec.md` build order TDD-first. Ship 0.1.0.

---

## Appendix: File Pointers

- `.llm/python-chargepoint/python_chargepoint/client.py:79-362` — auth + endpoint implementations we're porting
- `.llm/python-chargepoint/python_chargepoint/types.py:90-114` — `HomeChargerStatus` field list
- `.llm/python-chargepoint/python_chargepoint/constants.py` — `DISCOVERY_API` URL
- `.llm/python-chargepoint/python_chargepoint/global_config.py` — discovery response shape
- `../montty/Justfile:132-178` — `inspect-*` recipe pattern (curl+jq wrappers over localhost debug server)
- `../montty/project.yml` — reference XcodeGen config
- `../montty/Sources/App/AppDelegate.swift:7` — NSApplicationDelegate pattern
- `../montty/Resources/montty.entitlements` — unsandboxed + hardened runtime
- `../limn/scripts/desktop-package.py` — reference codesign + notarize script (just-bootstrap will generate its own equivalent)
- `/Users/tednaleid/.claude/plugins/cache/tednaleid/just-bootstrap/0.1.6/skills/just-bootstrap/SKILL.md` — just-bootstrap workflow
- `/Users/tednaleid/.claude/plugins/cache/tednaleid/just-bootstrap/0.1.6/skills/just-bootstrap/references/justfile.md` — Swift macOS Justfile recipes
- `/Users/tednaleid/.claude/plugins/cache/tednaleid/just-bootstrap/0.1.6/skills/just-bootstrap/references/release.md` — Swift macOS release workflow
- `/Users/tednaleid/.claude/plugins/cache/tednaleid/just-bootstrap/0.1.6/skills/just-bootstrap/references/homebrew.md` — cask template
