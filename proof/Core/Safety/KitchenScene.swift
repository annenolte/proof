//
//  KitchenScene.swift
//  proof — Core / Safety
//
//  The pre-baked kitchen as a scene package.
//
//  Two ways in, one shape out:
//
//  * `ScenePackageBuilder.package(from:)` reads the live 3D room — the authored kitchen from
//    the Tremor repository — and measures every catalogued object's real resting bounds.
//  * `KitchenScene.bundled()` reads `kitchen.scene.json`, which is that same measurement
//    written to disk once (`-proofExportScene`), so the engine can run without building any
//    geometry: in the onboarding card, in the Rooms tab and in the unit tests.
//

import Foundation

enum KitchenScene {

    static let resourceName = "kitchen.scene"

    /// Plain statement of where the scene came from. Shown in the UI, never embellished.
    static let provenance = "Object bounds are measured from the 3D model; surface heights come from its dimensions."

    static func bundled(_ bundle: Bundle = .main) -> ScenePackage? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScenePackage.self, from: data)
    }

    static func encode(_ package: ScenePackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(package)
    }

    /// Numbers repeated labels ("Dining chair 1", "Dining chair 2") so a list of flags can
    /// be read without the sky beside it. Order is by id, so numbering is stable.
    static func disambiguated(_ objects: [SceneObject]) -> [SceneObject] {
        let counts = Dictionary(grouping: objects, by: \.label).mapValues(\.count)
        var seen: [String: Int] = [:]
        return objects.sorted { $0.id < $1.id }.map { object in
            guard (counts[object.label] ?? 0) > 1 else { return object }
            var copy = object
            let n = (seen[object.label] ?? 0) + 1
            seen[object.label] = n
            copy.label = "\(object.label) \(n)"
            return copy
        }
    }
}
