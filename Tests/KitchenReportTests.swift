import XCTest
@testable import proof

/// Prints what the engine finds in the bundled kitchen at each stage. Not an accuracy
/// claim — the developer reviews these by hand (CLAUDE.md Stage 5, docs/EVAL.md).
final class KitchenReportTests: XCTestCase {
    func testPrintKitchenReport() throws {
        let package = try XCTUnwrap(KitchenScene.bundled())
        for stage in AgeStage.allCases {
            let a = SafetyEngine.analyze(package.objects, parameters: .forStage(stage))
            print("[proof] ── \(stage.title): \(a.flags.count) flags, \(a.chains.count) chains")
            for chain in a.chains { print("[proof]   \(chain.why)") }
            let notReached = a.flags.filter { $0.reachability == .notReached }.map(\.label)
            print("[proof]   not reached: \(notReached.joined(separator: ", "))")
        }
    }
}
