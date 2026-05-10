import Foundation
import Combine

/// Drives the 5-minute engagement-ramp recompute that the formula's
/// `E(I, t)` term depends on. Lives at app/scene level so any active
/// `StressViewModel` (Stress tab or Home sparkline) re-evaluates when
/// the clock ticks past a ramp boundary.
@MainActor
final class StressTimerService: ObservableObject {
    static let shared = StressTimerService()

    @Published var tickerPulse: Date = .distantPast

    private var cancellable: AnyCancellable?

    private init() {}

    func start() {
        stop()
        cancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.tickerPulse = now
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}
