# grounded

A signed, notarized macOS menubar app that monitors a home ChargePoint EV
charger and fires persistent macOS notifications on state changes — so you
find out *during the night* when an overnight charge failed, not in the
morning when your car is still empty.

## Install

### Homebrew

```bash
brew install --cask tednaleid/grounded/grounded
```

To upgrade to the latest version:

```bash
brew update && brew upgrade --cask grounded
```

### Manual download

Download the latest DMG from [Releases](https://github.com/tednaleid/grounded/releases).

## Build from source

Requires macOS 14+, Xcode 26, [xcodegen](https://github.com/yonaskolb/XcodeGen),
[swiftlint](https://github.com/realm/SwiftLint), and
[just](https://github.com/casey/just).

```bash
brew install xcodegen swiftlint just
just generate    # generate grounded.xcodeproj from project.yml
just check       # core purity + lint + all tests + build
just dev         # build and launch detached
just test        # run all tests (optional filter: just test ChargerState)
```

See [`CLAUDE.md`](CLAUDE.md) for the full set of recipes and the three
non-negotiable rules this codebase follows (red/green TDD, hexagonal
architecture, Justfile is the command surface).

## Architecture

`grounded` is built hexagonally:

- **`Sources/Core/`** — pure Foundation domain: `ChargerState`, classifier,
  `ChargerMonitor` orchestrator, `MonitoringTick` state machine,
  `MonitoringConfig`. Contains no UI or system framework imports. Enforced
  in CI by a grep step.
- **`Sources/Core/Ports/`** — protocols the Core needs to reach the outside
  world: `ChargerStatusSource`, `CredentialStore`, `NotificationSink`,
  `BrowserAuth`, `Clock`, `StateObserver`.
- **`Sources/Adapters/`** — concrete implementations of Ports:
  `ChargePointAPI/` (URLSession), `Keychain/` (Security),
  `Notifications/` (UserNotifications), `WebKit/` (WebKit login harvest),
  `System/` (wall clock), `AppKit/` (NSStatusItem), `Debug/` (inspect HTTP
  server, DEBUG only).
- **`Sources/App/`** — composition root: `@main`, `AppDelegate`,
  `LoginFlow`, wires adapters into the Core.

## Design docs

Authoritative design lives under
[`docs/specs/2026-04-11-grounded-menubar-app/`](docs/specs/2026-04-11-grounded-menubar-app/):

- [`contract.md`](docs/specs/2026-04-11-grounded-menubar-app/contract.md) —
  problem statement, state model, architecture, decisions locked in
- [`phase-1-spec.md`](docs/specs/2026-04-11-grounded-menubar-app/phase-1-spec.md) —
  scaffolding + infrastructure (done)
- [`phase-2-spec.md`](docs/specs/2026-04-11-grounded-menubar-app/phase-2-spec.md) —
  TDD-first core + adapters + wire-up

## Third-party notices

The ChargePoint API test fixtures under `Tests/Fixtures/chargepoint/`
are derived from
[python-chargepoint](https://github.com/mbillow/python-chargepoint)
(© 2022 Marc Billow, MIT). Full attribution is in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## License

[MIT](LICENSE)
