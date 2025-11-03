//
//  ComputationalObjectsSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//
import PoieticCore


/// System that ...
///
/// - **Input:** Simulation objects (is `Stock` || is `FlowRate` || has trait `Auxiliary`)
/// - **Output:**
///     - Ordered list of objects in ``SimulationOrderComponent``.
///     - Role associated with each object in ``SimulationRoleComponent``.
/// - **Forgiveness:** ...
///
struct SimulationOrderDependencySystem: System {
    func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        // TODO: Replace with SimulationObject trait once we have it (there are practical reasons we don't yet)
        // TODO: Should we use Trait.Stock? (also below)
        // Note: See roles below
        let unordered: [ObjectSnapshot] = frame.filter {
            ($0.type === ObjectType.Stock
                || $0.type === ObjectType.FlowRate
                || $0.type.hasTrait(Trait.Auxiliary))
        }

        // 2. Sort nodes based on computation dependency.
        let parameterEdges:[EdgeObject] = frame.edges.filter {
            $0.object.type === ObjectType.Parameter
        }

        let parameterDependency = Graph(nodes: unordered.map { $0.objectID },
                                        edges: parameterEdges)
        
        guard let ordered = parameterDependency.topologicalSort() else {
            let cycleEdges = parameterDependency.cycles()
            var nodes: Set<ObjectID> = Set()
            
            for edge in cycleEdges {
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                frame.appendIssue(ObjectIssue.computationCycle, for: edge.key)
            }
            for node in nodes {
                frame.appendIssue(ObjectIssue.computationCycle, for: node)
            }
            return
        }
        let snapshots = ordered.compactMap { frame[$0] }

        var stocks: [ObjectID] = []
        var flows: [ObjectID] = []
        
        // Determine simulation role: stock, flow, aux
        // Note: See filter at the beginning of the method
        for object in snapshots {
            let role: SimulationObject.Role

            // TODO: Should we use Trait.Stock?
            if object.type === ObjectType.Stock {
                role = .stock
                stocks.append(object.objectID)
            }
            else if object.type === ObjectType.FlowRate {
                role = .flow
                flows.append(object.objectID)
            }
            else if object.type.hasTrait(Trait.Auxiliary) {
                role = .auxiliary
            }
            else {
                throw InternalSystemError(self,
                                          message: "Unknown simulation object role for object type: \(object.type.name)",
                                          context: .object(object.objectID))
            }
            let comp = SimulationRoleComponent(role: role)
            frame.setComponent(comp, for: object.objectID)
        }
        
        let component = SimulationOrderComponent(
            objects: snapshots,
            stocks: stocks,
            flows: flows
        )

        frame.setFrameComponent(component)
    }
}

/// System that collects object names and creates a name lookup.
///
/// - **Input:** Ordered simulation objects in frame component ``SimulationOrderComponent``.
/// - **Output:** ``NamedObjectComponent`` for objects where the name is present and not visually
///               empty; ``SimulationNameLookupComponent`` for the frame.
/// - **Forgiveness:** Objects without name attribute set - assumed they can't be referred to by
///   name, but can by other means, such as an edge.
/// - **Issues collected:** Objects with duplicate name.
///
struct NameCollectorSystem: System {
    // Note: In the future this system might be doing fully qualified name resolution, once we get
    //       nested simulation blocks.
    
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(SimulationOrderDependencySystem.self),
    ]

    func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        guard let order = frame.frameComponent(SimulationOrderComponent.self) else {
            return
        }
        
        var namedObjects: [String: [ObjectID]] = [:]
        var nameLookup: [String:ObjectID] = [:]
        

        // 1. Collect names
        for object in order.objects {
            guard let name = object.name else { continue }
            
            // Is visually empty?
            // TODO: Bring String.isVisuallyEmpty method from poietic-godot to core
            if name.isEmpty || name.allSatisfy({ $0.isWhitespace}) {
                frame.appendIssue(ObjectIssue.emptyName, for: object.objectID)
            }
            namedObjects[name, default: []].append(object.objectID)
            let comp = SimObjectNameComponent(name: name)
            frame.setComponent(comp, for: object.objectID)
        }
        
        // 2. Find duplicates
        for (name, ids) in namedObjects where ids.count > 1 {
            guard ids.count == 1 else {
                let issue = ObjectIssue.duplicateName(name)
                for id in ids {
                    frame.appendIssue(issue, for: id)
                }
                continue
            }
            nameLookup[name] = ids[0]
        }

        let component = SimulationNameLookupComponent(
            namedObjects: nameLookup
        )
        frame.setFrameComponent(component)
    }
}
