//
//  NameResolutionSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//

import PoieticCore

/// System that collects object names and creates a name lookup.
///
/// - **Input:** Ordered simulation objects in frame component ``SimulationOrderComponent``.
/// - **Output:** ``NamedObjectComponent`` for objects where the name is present and not visually
///               empty; ``SimulationNameLookupComponent`` for the frame.
/// - **Forgiveness:** Objects without name attribute set - assumed they can't be referred to by
///   name, but can by other means, such as an edge.
/// - **Issues collected:** Objects with duplicate name.
///
public struct NameResolutionSystem: System {
    // Note: In the future this system might be doing fully qualified name resolution, once we get
    //       nested simulation blocks.
    public init() {}
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ComputationOrderSystem.self),
    ]

    public func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        guard let order = frame.frameComponent(SimulationOrderComponent.self) else {
            return
        }
        
        var namedObjects: [String: [ObjectID]] = [:]
        var nameLookup: [String:ObjectID] = [:]

        for object in order.objects {
            guard let name = object.name else { continue }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                let issue = Issue(
                    identifier: "empty_name",
                    severity: .error,
                    system: self,
                    error: ModelError.emptyName,
                    )
                frame.appendIssue(issue, for: object.objectID)
                continue
            }
            namedObjects[trimmedName, default: []].append(object.objectID)
        }
        
        // 2. Find duplicates
        for (name, ids) in namedObjects where ids.count >= 1 {
            guard ids.count == 1 else {
                let issue = Issue(
                    identifier: "duplicate_name",
                    severity: .error,
                    system: self,
                    error: ModelError.duplicateName(name),
                    )
                // TODO: Add related nodes
                for id in ids {
                    frame.appendIssue(issue, for: id)
                }
                continue
            }
            nameLookup[name] = ids[0]
            let comp = SimulationObjectNameComponent(name: name)
            frame.setComponent(comp, for: ids[0])
        }

        let component = SimulationNameLookupComponent(
            namedObjects: nameLookup
        )
        frame.setFrameComponent(component)
    }
}
