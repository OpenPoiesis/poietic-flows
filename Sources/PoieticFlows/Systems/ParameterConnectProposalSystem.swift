//
//  AutoParameterProposalSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 09/11/2025.
//

import PoieticCore

/// Component that proposes parameter edges to be created or removed.
///
/// The component is created by the ``ParameterConnectionProposalSystem`` and is typically
/// set as a singleton component.
///
public struct ParameterProposal: Component {
    public struct EdgeProposal {
        public let origin: ObjectID
        public let target: ObjectID
    }
    /// IDs of unused parameter edges.
    public let toRemove: [ObjectID]
    /// Endpoints of edges to be created. Create edges of type `Parameter`.
    public let toAdd: [EdgeProposal]
    
    /// Flag whether there are any parameters to be removed or added.
    ///
    public var isEmpty: Bool { toRemove.isEmpty && toAdd.isEmpty }
}

/// System that proposes parameter edges to be added and to be removed. The proposal is based on
/// the parameter names used in parsed expressions (typically from `formula` attribute) and
///
/// - **Input:** Singleton ``SimulationNameLookupComponent``
///   and objects with ``ResolvedParametersComponent``.
///
///   If a singleton ``Selection`` is present, then only relevant objects in the selection are
///   considered.
///
/// - **Output:** ``ParameterProposal`` singleton.
/// - **Forgiveness:** Nothing is proposed if the singleton is missing.
/// - **Issues:** No issues created.
///
/// After updating the world using the system, one can remove and create parameter edges
/// as follows:
///
/// ```swift
/// // Assume the world and trans are given as:
/// let world: World
/// let trans: TransientFrame
///
/// let proposal: ParameterProposal = world.singleton()!
///
/// for id in proposal.toRemove {
///     trans.removeCascading(id)
/// }
/// for edgeProposal in proposal.toAdd {
///     trans.createEdge(.Parameter,
///                      origin: edgeProposal.origin,
///                      target: edgeProposal.target)
/// }
/// ```

public class ParameterConnectionProposalSystem: System {
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(NameResolutionSystem.self),
        .after(ParameterResolutionSystem.self), // We need variable names
    ]
    public required init() {}
    public func update(_ world: World) throws (InternalSystemError) {
        guard let lookup: SimulationNameLookupComponent = world.singleton()
        else { return }
        
        let selection: Selection? = world.singleton()
        
        var toRemove: [ObjectID] = []
        var toAdd: [ParameterProposal.EdgeProposal] = []
        
        for (entityID, resolution) in world.query(ResolvedParametersComponent.self) {
            guard let objectID = world.entityToObject(entityID)
            else { continue }
            if let selection, !selection.contains(objectID) { continue }

            toRemove += resolution.unused
            
            for name in resolution.missing {
                guard let parameterID = lookup.namedObjects[name]
                else { continue }
                
                let edge = ParameterProposal.EdgeProposal(origin: parameterID, target: objectID)
                toAdd.append(edge)
            }
        }
        let proposal = ParameterProposal(toRemove: toRemove, toAdd: toAdd)
        world.setSingleton(proposal)
    }
}
