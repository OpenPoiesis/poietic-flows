//
//  ComputationalObjectsSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//

import PoieticCore

/// System that collects objects for computation and orders them by computational dependency.
///
/// The computational dependency is determined by edges of type `Parameter`.
///
/// - **Input:** Simulation objects (is `Stock` || is `FlowRate` || has trait `Auxiliary`)
/// - **Output:**
///     - Ordered list of objects in ``SimulationOrder``.
///     - Role associated with each object in ``SimulationRole``.
/// - **Forgiveness:** Nothing to be forgiven.
/// - **Issues Appended:**
///     - `computation_cycle`: Node is part of a computation cycle.
///
public struct ComputationOrderSystem: System {
    public static let IssueSourceName = "ComputationOrderSystem"
    
    public static func update(_ world: World) throws (InternalSystemError) {
        guard let plane = world.plane
        else { return }
        
        guard let snapshots = orderedSnapshots(world: world, plane: plane) else {
            return
        }

        var stocks: [ObjectID] = []
        var flows: [ObjectID] = []
        
        for (object, role) in snapshots {
            guard let entity = world.entity(object.objectID) else { continue  /* Error? */ }

            switch role {
            case .stock: stocks.append(object.objectID)
            case .flow: flows.append(object.objectID)
            case .auxiliary: break
                
            }
            entity.setComponent(role)
        }
        
        let objects = snapshots.map { $0.object }
        let orderComponent = SimulationOrder( objects: objects )
        
        world.setSingleton(orderComponent)
    }
    
    static func filterSimulationObjects(plane: DesignPlane) -> [ObjectID:SimulationRole] {
        var result: [ObjectID:SimulationRole] = [:]
        for object in plane.snapshots {
            let role: SimulationRole

            // TODO: Should we use Trait.Stock?
            if object.type === ObjectType.Stock {
                role = .stock
            }
            else if object.type === ObjectType.FlowRate {
                role = .flow
            }
            else if object.type.hasTrait(Trait.Auxiliary) {
                role = .auxiliary
            }
            else { // Not a simulation object
                continue
            }
            result[object.objectID] = role
        }
        return result
    }
    
    static func orderedSnapshots(world: World, plane: DesignPlane) -> [(object: ObjectSnapshot, role: SimulationRole)]? {
        // TODO: Replace with SimulationObject trait once we have it (there are practical reasons we don't yet)
        // TODO: Should we use Trait.Stock?
        let unordered = filterSimulationObjects(plane: plane)

        let parameterEdges:[DesignObjectEdge] = plane.edges.filter {
            $0.object.type === ObjectType.Parameter
        }

        let parameterDependency = Graph(nodes: Array(unordered.keys),
                                        edges: parameterEdges)
        
        guard let ordered:[ObjectID] = parameterDependency.topologicalSort() else {
            let cycleEdges = parameterDependency.cycles()
            var nodes: Set<ObjectID> = Set()
            
            for edge in cycleEdges {
                guard let entity = world.entity(edge.id) else { continue }
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                let issue = Issue(
                    identifier: IssueIdentifier.computationCycle,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Edge is part of a computation cycle",
                )
                entity.appendIssue(issue)
            }
            for node in nodes {
                guard let entity = world.entity(node) else { continue }
                let issue = Issue(
                    identifier: IssueIdentifier.computationCycle,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Node is part of a computation cycle",
                    hints: [
                        "Disconnect at least one of the parameter connections that is causing the cycle"
                    ]
                )
                entity.appendIssue(issue)
            }
            return nil
        }

        let result: [(object: ObjectSnapshot, role: SimulationRole)] = ordered.compactMap {
            guard let snapshot = plane[$0],
                  let role = unordered[$0]
            else { return nil }
            return (object: snapshot, role: role)
        }
        return result
    }
}

