import Foundation

/// The orchestrator. An `actor` that owns a `MonitorState` and drives the
/// polling loop via injected ports. Pure Core — no framework imports — so
/// it can live alongside the Core types and be exercised by the integration
/// test target without pulling in `@main` from `Sources/App/`.
actor ChargerMonitor {
    private(set) var state: MonitorState
    private let statusSource: ChargerStatusSource
    private let credentialStore: CredentialStore
    private let notificationSink: NotificationSink
    private let clock: GroundedClock
    private let config: MonitoringConfig
    private var observers: [StateObserver] = []
    private var pollingTask: Task<Void, Never>?

    init(
        statusSource: ChargerStatusSource,
        credentialStore: CredentialStore,
        notificationSink: NotificationSink,
        clock: GroundedClock,
        config: MonitoringConfig = .default,
        initialState: MonitorState = .initial
    ) {
        self.statusSource = statusSource
        self.credentialStore = credentialStore
        self.notificationSink = notificationSink
        self.clock = clock
        self.config = config
        self.state = initialState
    }

    /// Snapshot of the current monitor state. Used by the menubar controller
    /// and by the debug inspect surface.
    func currentState() -> MonitorState {
        state
    }

    func addObserver(_ observer: StateObserver) {
        observers.append(observer)
    }

    /// Drive a single poll tick: fetch, classify, update state, notify.
    /// Integration tests call this directly; production wiring invokes it
    /// from the polling loop started via `start()`.
    func performTick() async {
        let result = await fetchResult()
        await handle(result: result)
    }

    /// Debug helper — inject `count` consecutive failures with the given
    /// category directly into the state machine, bypassing the network.
    /// Used by the inspect surface's `simulate-failure` endpoint to drive
    /// the threshold machinery during hand-testing.
    func injectFailures(_ category: APIErrorCategory, count: Int) async {
        for _ in 0..<count {
            await handle(result: .failure(category))
        }
    }

    /// Launch the background polling loop. First tick happens immediately,
    /// subsequent ticks wait `config.pollInterval` via the injected clock.
    /// Safe to call multiple times — idempotent.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// Cancel the polling loop. Any in-flight tick completes; subsequent
    /// ones are not scheduled.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private

    private func runLoop() async {
        while !Task.isCancelled {
            await performTick()
            if Task.isCancelled { break }
            do {
                try await clock.sleep(for: .seconds(config.pollInterval))
            } catch {
                break
            }
        }
    }

    private func fetchResult() async -> Result<HomeChargerSnapshot, APIErrorCategory> {
        // Missing credentials short-circuits to the auth fast-path without
        // touching the network.
        if await !credentialStore.hasCredentials {
            return .failure(.authFailure)
        }
        do {
            let snapshot = try await statusSource.fetchStatus()
            return .success(snapshot)
        } catch let category as APIErrorCategory {
            return .failure(category)
        } catch {
            return .failure(.networkFailure)
        }
    }

    private func handle(result: Result<HomeChargerSnapshot, APIErrorCategory>) async {
        let now = await clock.now()
        let outcome = MonitoringTick.tick(
            previous: state,
            result: result,
            at: now,
            config: config
        )

        let previousVisible = state.visibleState
        state = outcome.newState

        if let transition = outcome.transition, !transition.isNoOp {
            for observer in observers {
                await observer.stateDidChange(from: previousVisible, to: state.visibleState)
            }
        }

        if let notification = outcome.notification {
            await notificationSink.deliver(
                title: notification.title,
                body: notification.body
            )
        }
    }
}
