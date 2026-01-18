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
/// - **Output:** ``SimulationObjectNameComponent`` for objects where the name is present and not visually
///               empty; ``SimulationNameLookupComponent`` for the frame.
/// - **Forgiveness:** Objects without name attribute set - assumed they can't be referred to by
///   name, but can by other means, such as an edge.
/// - **Issues collected:** Objects with duplicate name.
///
public struct NameResolutionSystem: System {
    // Note: In the future this system might be doing fully qualified name resolution, once we get
    //       nested simulation blocks.
    public init(_ world: World) { }
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ComputationOrderSystem.self),
    ]

    public func update(_ world: World) throws (InternalSystemError) {
        guard let order: SimulationOrderComponent = world.singleton() else {
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
                world.appendIssue(issue, for: object.objectID)
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
                    world.appendIssue(issue, for: id)
                }
                continue
            }
            nameLookup[name] = ids[0]
            let comp = SimulationObjectNameComponent(name: name)
            world.setComponent(comp, for: ids[0])
        }

        let component = SimulationNameLookupComponent(
            namedObjects: nameLookup
        )
        world.setSingleton(component)
    }

}
