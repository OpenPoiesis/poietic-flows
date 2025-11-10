//
//  ComputationalObjectsSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//

import PoieticCore

/// System that collects objects for computation and orders them by computational dependency.
///
/// The computational dependency is determined by edges of type ``ObjectType/Parameter``.
///
/// - **Input:** Simulation objects (is `Stock` || is `FlowRate` || has trait `Auxiliary`)
/// - **Output:**
///     - Ordered list of objects in ``SimulationOrderComponent``.
///     - Role associated with each object in ``SimulationRoleComponent``.
/// - **Forgiveness:** ...
///
public struct ComputationOrderSystem: System {
    public init() {}
    public func update(_ frame: AugmentedFrame) throws (InternalSystemError) {
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
                let issue = Issue(
                    identifier: "computation_cycle",
                    severity: .error,
                    system: self,
                    error: ModelError.computationCycle,
                    )
                frame.appendIssue(issue, for: edge.key)
            }
            for node in nodes {
                let issue = Issue(
                    identifier: "computation_cycle",
                    severity: .error,
                    system: self,
                    error: ModelError.computationCycle,
                    )
                frame.appendIssue(issue, for: node)
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
            frame.setComponent(comp, for: .object(object.objectID))
        }
        
        let component = SimulationOrderComponent(
            objects: snapshots,
            stocks: stocks,
            flows: flows
        )

        frame.setComponent(component, for: .Frame)
    }
}

