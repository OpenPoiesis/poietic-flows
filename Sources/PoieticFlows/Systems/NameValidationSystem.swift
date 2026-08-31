//
//  NameValidationSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//

import PoieticCore


/// Set by NameValidationSystem to tag objects with duplicate or reserved names.
///
/// Those objects should not be further processed by the planner.
///
public struct InvalidName: TagComponent {
    public typealias Storage = TagComponentStorage<Self>
    public init() {}
}

/// System that validates object names and creates a name lookup.
///
/// - **Input:**
///     - Ordered simulation objects in plane component ``SimulationOrder`` and
///       with the ``NormalizedName`` component.
/// - **Output:**
///     -  ``SimulationNameLookup`` for the plane if all names are successfully validated.
///     - Sets ``InvalidName`` component from entities with duplicate or reserved names.
/// - **Forgiveness:** Objects without name attribute set - assumed they can't be referred to by
///   name, but can by other means, such as an edge.
/// - **Issues collected:**
///     - `empty_name`: Name is empty (no characters) or visually empty – contains only whitespaces.
///     - `duplicate_name`: The node has the same name as some other node.
///     - `reserved_name`: The node has same name as a built-in variable.
///
/// - Note: Visually empty names are handled in ``NameNormalizationSystem`` – those entities
///         do not have the normalised name component set.
///
public struct NameValidationSystem: System {
    public static let IssueSourceName = "NameValidationSystem"

    // Note: In the future this system might be doing fully qualified name resolution, once we get
    //       nested simulation blocks.
    public static let dependencies: [SystemDependency] = [
        .after(NameNormalizationSystem.self),
        .after(ComputationOrderSystem.self),
    ]

    public static func update(_ world: World) throws (InternalSystemError) {
        guard let order: SimulationOrder = world.singleton() else {
            return
        }
        
        var namedObjects: [String: [ObjectID]] = [:]
        var nameLookup: [String:ObjectID] = [:]

        for object in order.objects {
            guard let entity = world.entity(object.objectID) else { continue }
            guard let normalizedName: NormalizedName = entity.component() else {
                throw InternalSystemError(self,
                                          message: "Missing normalized name component",
                                          context: .component(object.objectID, "NormalizedName"))
            }

            guard !normalizedName.isVisuallyEmpty else {
                // Someone must have set the component manually
                throw InternalSystemError(self,
                                          message: "Normalized name is empty",
                                          context: .component(object.objectID, "NormalizedName"))
            }
            
            // TODO: Add test
            guard !BuiltinVariable.normalizedKeys.contains(normalizedName.key) else {
                let issue = Issue(
                    identifier: IssueIdentifier.reservedName,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Object uses a reserved name",
                    hints: [ "Set a node name that one of reserved/built-in variable names" ],
                )
                entity.appendIssue(issue)
                entity.setComponent(InvalidName())
                continue
            }
            
            namedObjects[normalizedName.key, default: []].append(object.objectID)
        }
       
        // 2. Find duplicates
        for (name, ids) in namedObjects {
            if ids.count == 1 {
                let onlyID = ids[0]
                nameLookup[name] = onlyID
            }
            else if ids.count > 1 {
                // FIXME: We should use the display name in the error, not the normalised key
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
                    entity.setComponent(InvalidName())
                }
            }
        }
        let component = SimulationNameLookup(namedObjects: nameLookup)
        world.setSingleton(component)
    }
}
