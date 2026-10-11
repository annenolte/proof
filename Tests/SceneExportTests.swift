import XCTest
@testable import proof

/// Builds the authored kitchen, measures it, and checks the bundled package still matches.
///
/// When the scene changes, run with the file `/private/tmp/proof-export` present and copy
/// the printed path over `proof/Resources/kitchen.scene.json`.
@MainActor
final class SceneExportTests: XCTestCase {

    func testMeasuredKitchenMatchesBundledPackage() async throws {
        let materials = await DemoMaterials.make()
        let scene = ApartmentScene(materials: materials)
        scene.build()
        let measured = ScenePackageBuilder.package(from: scene)
        XCTAssertGreaterThan(measured.objects.count, 20)

        if FileManager.default.fileExists(atPath: "/private/tmp/proof-export") {
            let url = URL(fileURLWithPath: "/private/tmp/proof-kitchen.scene.json")
            try KitchenScene.encode(measured).write(to: url)
            print("[proof] exported \(measured.objects.count) objects to \(url.path)")
            return
        }

        let bundled = try XCTUnwrap(KitchenScene.bundled(), "kitchen.scene.json is missing")
        XCTAssertEqual(Set(bundled.objects.map(\.id)), Set(measured.objects.map(\.id)))
    }
}
