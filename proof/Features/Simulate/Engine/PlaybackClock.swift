import Foundation
import CoreMedia
import RealityKit

/// Playback speed for the stage.
///
/// RealityKit advances at most one 1/60 s physics step per host frame tick, so
/// there is no fast-forward — only real time and slower. The slower rates are
/// implemented by handing `PhysicsSimulationComponent` a `CMTimebase` running at
/// that rate, which slows the *whole* simulation. The accelerogram is then
/// sampled by simulation time, so 0.25× is genuinely slower rather than the same
/// motion played back choppily.
public enum PlaybackRate: Double, CaseIterable, Sendable, Identifiable {
    case quarter = 0.25
    case half = 0.5
    case normal = 1.0

    public var id: Double { rawValue }

    public var displayName: String {
        switch self {
        case .quarter: return "0.25×"
        case .half: return "0.5×"
        case .normal: return "1×"
        }
    }
}

/// Owns the simulation clock: rate, pause, and the mapping from physics steps to
/// simulation seconds.
@MainActor
public final class PlaybackClock {

    /// The timebase driving `PhysicsSimulationComponent.clock`, when one could
    /// be created. Nil on the fallback path.
    public private(set) var timebase: CMTimebase?
    /// True when the timebase is actually driving the simulation, which is what
    /// makes slow motion slow the physics rather than only the excitation.
    public var isTimebaseActive: Bool { timebase != nil }

    public private(set) var rate: PlaybackRate = .normal
    public private(set) var isRunning = false

    public init() {
        var created: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &created)
        if status == noErr, let created {
            CMTimebaseSetTime(created, time: .zero)
            CMTimebaseSetRate(created, rate: 0)
            timebase = created
        }
    }

    /// Installs the clock on a simulation root. Safe to call more than once.
    public func attach(to simulationRoot: Entity) {
        guard let timebase,
              var simulation = simulationRoot.components[PhysicsSimulationComponent.self]
        else { return }
        simulation.clock = timebase
        simulationRoot.components.set(simulation)
    }

    public func start() {
        isRunning = true
        applyRate()
    }

    public func stop() {
        isRunning = false
        applyRate()
    }

    public func setRate(_ newRate: PlaybackRate) {
        rate = newRate
        applyRate()
    }

    /// Rewinds the timebase itself. The simulation's own notion of elapsed time
    /// is tracked by `EarthquakeSimulator`; this only keeps the two from
    /// drifting apart over a long session.
    public func rewind() {
        guard let timebase else { return }
        CMTimebaseSetTime(timebase, time: .zero)
    }

    private func applyRate() {
        guard let timebase else { return }
        CMTimebaseSetRate(timebase, rate: isRunning ? Float64(rate.rawValue) : 0)
    }

    // MARK: - The mapping

    /// How much **simulation** time one physics step represents.
    ///
    /// With the timebase active, RealityKit has already slowed the delivery of
    /// steps, so a step is a full 1/60 s of simulation time. Without it we fall
    /// back to scaling the excitation clock instead, which still makes the
    /// shaking slower — just not the free-fall.
    public static func simulationAdvance(
        deltaTime: Double, rate: PlaybackRate, isTimebaseActive: Bool
    ) -> Double {
        isTimebaseActive ? deltaTime : deltaTime * rate.rawValue
    }

    /// Wall-clock seconds one second of simulation takes at a given rate.
    public static func wallClockDuration(
        simulationSeconds: Double, rate: PlaybackRate
    ) -> Double {
        simulationSeconds / rate.rawValue
    }
}
