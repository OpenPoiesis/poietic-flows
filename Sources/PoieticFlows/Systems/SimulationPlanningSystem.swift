//
//  ComputationalObjectsSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 30/10/2025.
//
import PoieticCore

public struct SimulationOrderComponent: Component {
    let objects: [ObjectSnapshot]
}

public struct NameIndexComponent: Component {
    let nameToIndex: [String:Int]
}


/// System that ...
///
/// - **Input:** ...
/// - **Output:** ...
/// - **Forgiveness:** ...
///
struct SimulationObjectsCollectorSystem: System {
    func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        let unordered: [ObjectSnapshot] = frame.filter {
            ($0.type === ObjectType.Stock
                || $0.type === ObjectType.FlowRate
                || $0.type.hasTrait(Trait.Auxiliary))
        }

        var homonyms: [String: [ObjectID]] = [:]
        
        // 1. Collect nodes relevant to the simulation
        for node in unordered {
            guard let name = node.name else { continue }
            
            // Is visually empty?
            if name.isEmpty || name.allSatisfy({ $0.isWhitespace}) {
                frame.appendIssue(ObjectIssue.emptyName, for: node.objectID)
            }
            homonyms[name, default: []].append(node.objectID)
        }
        
        var dupes: [String] = []
        
        for (name, ids) in homonyms where ids.count > 1 {
            let issue = ObjectIssue.duplicateName(name)
            dupes.append(name)
            for id in ids {
                frame.appendIssue(issue, for: id)
            }
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
        let component = SimulationOrderComponent(objects: snapshots)
        frame.setFrameComponent(component)
    }
}

