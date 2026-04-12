# grounded

macOS menubar app that watches Ted's home ChargePoint charger and fires
persistent notifications on state changes. Signed, notarized, distributed via
a dedicated Homebrew cask tap (`tednaleid/homebrew-grounded`).

Authoritative design lives in `docs/specs/2026-04-11-grounded-menubar-app/`.
Read `contract.md` before any non-trivial change.

## The three rules

### 1. Red/green TDD — always

No production code lands without a failing test first. Workflow:

1. Write one failing `@Test` (Swift Testing, not XCTest) for the behavior you want.
2. Run `just test-core` (or `test-adapters` / `test-integration`) and **watch it fail**.
   If you didn't watch it fail, you don't know it tests anything real.
3. Write the minimum code to make it pass.
4. Run `just check` — everything stays green, commit.

Bug fixes are the same: reproduce the bug as a failing test first.
Skipping any of these steps is skipping TDD, which is not allowed on this
codebase.

### 2. Hexagonal architecture

```
Sources/
├── App/        -- composition root (@main, AppDelegate, LoginFlow)
├── Core/       -- pure Foundation. No framework imports.
│   └── Ports/  -- protocols the Core needs (still Foundation-only)
└── Adapters/   -- implementations of Ports that touch the outside world
    ├── ChargePointAPI/   (URLSession)
    ├── Keychain/         (Security)
    ├── Notifications/    (UserNotifications)
    ├── WebKit/           (WebKit)
    ├── System/           (Foundation wall clock)
    ├── AppKit/           (NSStatusItem + NSMenu)
    └── Debug/            (InspectServer, #if DEBUG only)
```

**`Sources/Core/` is pure Foundation.** It may not `import AppKit`, `UIKit`,
`WebKit`, `Security`, `UserNotifications`, or `URLSession`. `just check` runs
`check-core-purity` which greps every `Sources/Core/**/*.swift` for those
imports and fails if any match. This is enforced on every push.

If Core needs to reach the outside world, define a new `Port` in
`Sources/Core/Ports/` and an adapter in `Sources/Adapters/<Name>/`. Wire them
up in `Sources/App/`.

Core types are all `Sendable`. All concurrency is structured: `actor`,
`@MainActor`, `async let`, `Task`. No `DispatchQueue`, no completion handlers.

### 3. Justfile is the command surface

Every dev command goes through `just`. Never run `xcodebuild`, `swift test`,
or `swiftlint` directly — use the recipe. This keeps local dev, pre-commit,
and CI running exactly the same checks.

The core recipes you'll reach for daily:

| Recipe | What it does |
|---|---|
| `just check` | Full green-gate: core purity + lint + all tests + build. Used by CI and pre-commit. |
| `just test [name]` | All tests, optionally filtered (e.g. `just test ChargerState`). |
| `just test-core [name]` | Just the Core target (<1s, no framework deps). |
| `just test-adapters [name]` / `just test-integration [name]` | Scoped test targets. |
| `just build` | Debug build into `/tmp/grounded-build`. |
| `just dev` | Build and launch detached so `just inspect-state` can reach the debug server. |
| `just stop` | Quit the running app. |
| `just inspect-state` (+ other `inspect-*`) | Curl the debug HTTP server on `localhost:9877`. |
| `just lint` / `just fmt` | SwiftLint. |
| `just icon` | Regenerate the AppIcon PNGs from `bolt.car.circle`. |
| `just generate` | `xcodegen generate`. Every test/build recipe depends on this. |
| `just clean` | Remove build artifacts. Never `rm -rf` by hand. |
| `just bump 0.1.0` | Bump `CFBundleShortVersionString`, tag with release notes, push. |
| `just retag 0.1.0` | Re-trigger the release workflow for an existing version. |
| `just install-hooks` | One-time: install the git pre-commit hook that runs `just check`. |

## Toolchain

- Xcode 26.4, Swift 6 with strict concurrency `complete`, macOS 14.0 deployment target.
- XcodeGen (`project.yml`) — never hand-edit `.xcodeproj`. `grounded.xcodeproj`
  is generated and gitignored.
- Build output lives in `/tmp/grounded-build/` (not the repo) to avoid iCloud
  resource fork corruption of codesigning.
- Install the toolchain: `brew install swiftlint xcodegen just`.
