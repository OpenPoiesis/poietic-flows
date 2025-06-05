//
//  StockFlowView.swift
//
//
//  Created by Stefan Urbanek on 06/06/2023.
//

import PoieticCore

/// Status of a parameter.
///
/// The status is provided by the function ``StockFlowView/parameters(_:required:)``.
///
public enum ParameterStatus:Equatable {
    case missing
    case unused(node: ObjectID, edge: ObjectID)
    case used(node: ObjectID, edge: ObjectID)
}

/// Information about node parameters.
///
/// The status is provided by the function ``resolveParameters(_:required:)``.
///
public struct ResolvedParameters {
    public let missing: [String]
    // TODO: Change to [ObjectID] for edges
    public let unused: [EdgeObject]
}


/// View of Stock-and-Flow domain-specific aspects of the design.
///
/// The domain view provides higher level view of the design through higher
/// level concepts as defined in the ``FlowsMetamodel``.
///
/// The view assumes that the frame conforms to the metamodel and satisfies all of the
/// metamodel constraints.
///
public class StockFlowView {
    /// Graph that the view projects.
    ///
    public let frame: ValidatedFrame
    
    /// Create a new view on top of a graph.
    ///
    public init(_ frame: ValidatedFrame) {
        self.frame = frame
    }
    
    /// A list of nodes that are part of the simulation. The simulation nodes
    /// correspond to the simulation variables, where one node corresponds to
    /// exactly one simulation variable and vice-versa.
    ///
    /// - SeeAlso: ``StateVariable``, ``CompiledModel``
    ///
    public var simulationNodes: [ObjectSnapshot] {
        frame.filter {
            ($0.type === ObjectType.Stock
                || $0.type === ObjectType.FlowRate
                || $0.type.hasTrait(Trait.Auxiliary))
        }
    }
    
    // Parameter queries
    // ---------------------------------------------------------------------
    //
    public func incomingParameterEdges(_ target: ObjectID) -> [EdgeObject] {
        // TODO: (minor) We are unnecessarily doing lookup for target when we are fetching the edges
        return frame.incoming(target).filter {
            $0.object.type === ObjectType.Parameter
        }
    }
    /// Nodes representing parameters of a given node.
    ///
    public func incomingParameterNodes(_ nodeID: ObjectID) -> [ObjectSnapshot] {
        // TODO: In the compiler, do this once and create a map: originID -> [DesignObject]
        return incomingParameterEdges(nodeID).map { $0.originObject }
    }

    // Fills/drains queries
    // ---------------------------------------------------------------------
    //
    /// Selector for an edge originating in a flow and ending in a stock denoting
    /// which stock the flow fills. There must be only one of such edges
    /// originating in a flow.
    ///
    /// Neighbourhood of stocks around the flow.
    ///
    ///     FlowRate --(Flow)--> Stock
    ///      ^                     ^
    ///      |                     +--- Neighbourhood (only one)
    ///      |
    ///      *Node of interest*
    ///
    public func fills(_ flowID: ObjectID) -> ObjectID? {
        frame.outgoing(flowID).first {
            $0.object.type === ObjectType.Flow
        }?.target
    }
    
    /// Returns an ID of a node that the flow drains.
    ///
    /// Neighbourhood of stocks around the flow.
    ///
    ///     Stock --(Drains)--> Flow Rate
    ///      ^                    ^
    ///      |                    +--- Node of interest
    ///      |
    ///      Neighbourhood (only one)
    ///
    public func drains(_ flowID: ObjectID) -> ObjectID? {
        frame.incoming(flowID).first {
            $0.object.type === ObjectType.Flow
        }?.origin
    }

    /// Resolve missing and unused parameter connections.
    ///
    /// The Stock and Flow model requires that parameters are connected to the nodes where they are
    /// used. This is a user-oriented requirement.
    ///
    public func resolveParameters(_ nodeID: ObjectID, required: [String]) ->  ResolvedParameters {
        var missing: Set<String> = Set(required)
        var unused: [EdgeObject] = []
        
        for edge in incomingParameterEdges(nodeID) {
            let parameter = edge.originObject
            guard let parameterName = parameter.name else {
                preconditionFailure("Named node expected for parameter")
            }
            
            if missing.contains(parameterName) {
                missing.remove(parameterName)
            }
            else {
                unused.append(edge)
            }
        }
        
        return ResolvedParameters(missing: Array(missing), unused: unused)
    }
}
