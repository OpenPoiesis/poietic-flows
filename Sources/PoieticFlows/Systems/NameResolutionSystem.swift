//
//  NameResolutionSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//

import PoieticCore

/// System that collects object names and creates a name lookup.
///
/// - **Input:** Ordered simulation objects in plane component ``SimulationOrder``.
/// - **Output:** ``SimulationName`` for objects where the name is present and not visually
///               empty; ``SimulationNameLookup`` for the plane.
/// - **Forgiveness:** Objects without name attribute set - assumed they can't be referred to by
///   name, but can by other means, such as an edge.
/// - **Issues collected:**
///     - `empty_name`: Name is empty (no characters) or visually empty – contains only whitespaces.
///     - `duplicate_name`: The node has the same name as some other node.
///
public struct NameResolutionSystem: System {
    public static let IssueSourceName = "NameResolutionSystem"

    // Note: In the future this system might be doing fully qualified name resolution, once we get
    //       nested simulation blocks.
    public static let dependencies: [SystemDependency] = [
        .after(ComputationOrderSystem.self),
    ]

    public static func update(_ world: World) throws (InternalSystemError) {
        guard let order: SimulationOrder = world.singleton() else {
            return
        }
        
        var namedObjects: [String: [ObjectID]] = [:]
        var nameLookup: [String:ObjectID] = [:]

        for object in order.objects {
            guard let name = object.name,
                  let entity = world.entity(object.objectID)
            else { continue }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                let issue = Issue(
                    identifier: IssueIdentifier.emptyName,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Node name is empty",
                    hints: [ "Set a node name that is not visually empty" ],
                )
                entity.appendIssue(issue)
                continue
            }
            
            // TODO: Add test
            guard !BuiltinVariable.allNames.contains(trimmedName) else {
                let issue = Issue(
                    identifier: IssueIdentifier.reservedName,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Node uses a reserved name",
                    hints: [ "Set a node name that one of reserved/built-in variable names" ],
                )
                entity.appendIssue(issue)
                continue
            }
            
            namedObjects[trimmedName, default: []].append(object.objectID)
        }
       
        // 2. Find duplicates
        for (name, ids) in namedObjects {
            if ids.count == 1 {
                let onlyID = ids[0]
                nameLookup[name] = onlyID
                guard let entity = world.entity(onlyID) else { continue }
                let comp = SimulationName(name: name)
                entity.setComponent(comp)
            }
            else if ids.count > 1 {
                let issue = Issue(
                    identifier: IssueIdentifier.duplicateName,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Duplicate node name: '\(name)'",
                    hints: [ "Rename the node" ],
                )
                // TODO: Add related nodes
                for entity in world.query(ids) {
                    entity.appendIssue(issue)
                }
            }
        }
        let component = SimulationNameLookup(namedObjects: nameLookup)
        world.setSingleton(component)
    }
}
