import XCTest
import simd
@testable import proof

/// Synthetic scenes with known answers (CLAUDE.md Stage 5). Distances in metres.
final class EngineTests: XCTestCase {

    // MARK: Fixtures

    private func box(_ id: String, x: Float, z: Float, w: Float = 0.4, d: Float = 0.4,
                     bottom: Float = 0, top: Float) -> AABB {
        AABB(min: SIMD3(x - w / 2, bottom, z - d / 2), max: SIMD3(x + w / 2, top, z + d / 2))
    }

    private func object(_ id: String, role: ObjectRole, hazards: [HazardKind] = [],
                        aabb: AABB, surfaces: [Float] = []) -> SceneObject {
        SceneObject(id: id, label: id.capitalized, concept: id, role: role, hazards: hazards,
                    aabb: aabb, surfaces: surfaces, source: .auto, confidence: nil)
    }

    /// chair (seat 0.45) beside a counter (0.92) with a kettle on a shelf above it at 1.60 —
    /// out of reach from the floor and from the chair seat, within reach from the counter.
    private var chairCounterKettle: [SceneObject] {
        [
            object("chair", role: .climbable, aabb: box("chair", x: 0, z: 0, top: 0.90), surfaces: [0.45]),
            object("counter", role: .climbable, aabb: box("counter", x: 0.45, z: 0, w: 0.6, top: 0.92), surfaces: [0.92]),
            object("kettle", role: .hazard, hazards: [.heat],
                   aabb: box("kettle", x: 0.55, z: 0, w: 0.2, d: 0.2, bottom: 1.60, top: 1.85)),
        ]
    }

    private var climbing: SafetyParameters { .forStage(.climbing) }
    private var walking: SafetyParameters { .forStage(.walking) }
    private var crawling: SafetyParameters { .forStage(.crawling) }

    // MARK: Climb steps

    func testFloorToChairNeedsStepAtLeastSeatHeight() {
        let objects = chairCounterKettle
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        let seat = SafetyEngine.Node(objectID: "chair", height: 0.45)
        XCTAssertNil(SafetyEngine.climbStep(from: .floor, to: seat, objects: byID, parameters: walking))
        XCTAssertNotNil(SafetyEngine.climbStep(from: .floor, to: seat, objects: byID, parameters: climbing))
    }

    func testGapTooWideBreaksTheStep() {
        var objects = chairCounterKettle
        objects[1].aabb = box("counter", x: 1.5, z: 0, w: 0.6, top: 0.92)   // 1.0 m away
        let analysis = SafetyEngine.analyze(objects, parameters: climbing)
        XCTAssertTrue(analysis.chains.isEmpty)
    }

    // MARK: Chains

    func testChairCounterKettleIsAChainForAClimber() throws {
        let analysis = SafetyEngine.analyze(chairCounterKettle, parameters: climbing)
        let chain = try XCTUnwrap(analysis.chains.first)
        XCTAssertEqual(chain.nodeIDs, ["chair", "counter", "kettle"])
        XCTAssertTrue(chain.why.hasPrefix("Floor → Chair at 0.45 m"))
        XCTAssertEqual(analysis.flags(for: "kettle").first?.reachability, .viaChain(chainID: chain.id))
    }

    func testNoChainForAWalker() {
        let analysis = SafetyEngine.analyze(chairCounterKettle, parameters: walking)
        XCTAssertTrue(analysis.chains.isEmpty)
        XCTAssertEqual(analysis.flags(for: "kettle").first?.reachability, .notReached)
    }

    func testFloorReachableHazardMakesNoChain() {
        let objects = [object("cabinet", role: .hazard, hazards: [.chemicals],
                              aabb: box("cabinet", x: 0, z: 0, w: 0.6, top: 0.88))]
        let analysis = SafetyEngine.analyze(objects, parameters: crawling)
        XCTAssertTrue(analysis.chains.isEmpty)
        XCTAssertEqual(analysis.flags.first?.reachability, .fromFloor)
    }

    func testMultiSurfaceObjectStepsThroughItsOwnSurfaces() throws {
        // A stool with a footrail: floor → rail (0.20) → seat (0.68) only if the rail→seat
        // step fits. 0.48 fits the climbing stage (0.50), not walking (0.30).
        let objects = [
            object("stool", role: .climbable, aabb: box("stool", x: 0, z: 0, top: 1.0), surfaces: [0.20, 0.68]),
            // On a high shelf: out of reach from the rail, within reach from the seat.
            object("glass", role: .hazard, hazards: [.breakable],
                   aabb: box("glass", x: 0.30, z: 0, w: 0.08, d: 0.08, bottom: 1.40, top: 1.60)),
        ]
        let chain = try XCTUnwrap(SafetyEngine.analyze(objects, parameters: climbing).chains.first)
        XCTAssertEqual(chain.nodeIDs, ["stool", "glass"])        // the stool seat reaches it
        XCTAssertEqual(chain.relations.count, 3)                  // rail, seat, reach
        XCTAssertTrue(SafetyEngine.analyze(objects, parameters: walking).chains.isEmpty)
    }

    func testDeterministic() {
        let a = SafetyEngine.analyze(chairCounterKettle, parameters: climbing)
        let b = SafetyEngine.analyze(chairCounterKettle.reversed(), parameters: climbing)
        XCTAssertEqual(a.chains, b.chains)
        XCTAssertEqual(a.flags, b.flags)
    }

    // MARK: Heuristic flags

    func testTipOverByAspectRatio() {
        let tall = object("lamp", role: .hazard, hazards: [.tipOver],
                          aabb: box("lamp", x: 0, z: 0, w: 0.3, d: 0.3, top: 1.6))
        let squat = object("pouf", role: .hazard, hazards: [.tipOver],
                           aabb: box("pouf", x: 2, z: 0, w: 0.5, d: 0.5, top: 0.4))
        let flags = SafetyEngine.analyze([tall, squat], parameters: walking).flags
        XCTAssertEqual(flags.map(\.objectID), ["lamp"])
        XCTAssertTrue(flags[0].isHeuristic)
    }

    func testCornersOnlyInHeadHeightBand() {
        let coffee = object("coffee", role: .both, hazards: [.corners],
                            aabb: box("coffee", x: 0, z: 0, w: 1, top: 0.35))
        let bar = object("bar", role: .both, hazards: [.corners],
                         aabb: box("bar", x: 3, z: 0, w: 1, top: 1.05))
        let flags = SafetyEngine.analyze([coffee, bar], parameters: walking).flags
        XCTAssertEqual(flags.map(\.objectID), ["coffee"])
    }

    func testClusterWithinDistance() {
        let objects = [
            object("a", role: .hazard, hazards: [.heat], aabb: box("a", x: 0, z: 0, top: 0.5)),
            object("b", role: .hazard, hazards: [.sharp], aabb: box("b", x: 0.4, z: 0, top: 0.5)),
            object("c", role: .hazard, hazards: [.sharp], aabb: box("c", x: 3, z: 0, top: 0.5)),
        ]
        let clusters = SafetyEngine.analyze(objects, parameters: walking).relations.filter { $0.kind == .cluster }
        XCTAssertEqual(clusters.map(\.toID), ["b"])
    }

    // MARK: The bundled kitchen

    func testBundledKitchenLoadsAndProducesAStoolChainForAWalker() throws {
        let package = try XCTUnwrap(KitchenScene.bundled())
        XCTAssertGreaterThan(package.objects.count, 20)
        let analysis = SafetyEngine.analyze(package.objects, parameters: walking)
        XCTAssertFalse(analysis.chains.isEmpty)
        XCTAssertTrue(analysis.chains.contains { $0.nodeIDs.first?.hasPrefix("island.stool") == true })
    }
}
