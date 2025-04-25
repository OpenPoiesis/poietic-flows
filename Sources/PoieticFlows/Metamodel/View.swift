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


/// View of Stock-and-Flow domain-specific aspects of the design.
///
/// The domain view provides higher level view of the design through higher
/// level concepts as defined in the ``FlowsMetamodel``.
///
/// The view assumes that the frame conforms to the metamodel and satisfies all of the
/// metamodel constraints.
///
public class StockFlowView<F: Frame>{
    public typealias ViewedFrame = F
    
    /// Graph that the view projects.
    ///
    public let frame: ViewedFrame
    
    /// Create a new view on top of a graph.
    ///
    public init(_ frame: ViewedFrame) {
        self.frame = frame
    }
    
    /// A list of nodes that are part of the simulation. The simulation nodes
    /// correspond to the simulation variables, where one node corresponds to
    /// exactly one simulation variable and vice-versa.
    ///
    /// - SeeAlso: ``StateVariable``, ``CompiledModel``
    ///
    public var simulationNodes: [DesignObject] {
        frame.filter {
            $0.structure.type == .node
            && ($0.type === ObjectType.Stock
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
    public func incomingParameterNodes(_ nodeID: ObjectID) -> [DesignObject] {
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

    /// Information about node parameters.
    ///
    /// The status is provided by the function ``resolveParameters(_:required:)``.
    ///
    public struct ResolvedParameters {
        public let missing: [String]
        // TODO: Change to [ObjectID] for edges
        public let unused: [EdgeObject]
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

    /// Get a list of stock-to-stock adjacency.
    ///
    /// Two stocks are adjacent if there is a flow that connects the two stocks.
    /// One stock is being drained – origin of the adjacency,
    /// another stock is being filled – target of the adjacency.
    ///
    /// The following diagram depicts two adjacent stocks, where the stock `a`
    /// would be the origin and stock `b` would be the target:
    ///
    /// ```
    ///              Drains           Fills
    ///    Stock a ==========> Flow =========> Stock b
    ///       ^                                  ^
    ///       +----------------------------------+
    ///                  adjacent stocks
    ///
    /// ```
    ///
    public func stockAdjacencies() -> [StockAdjacency] {
        var adjacencies: [StockAdjacency] = []

        let flowNodes: [DesignObject] = frame.filter {
                $0.structure.type == .node
                && $0.type === ObjectType.FlowRate
            }

        for flow in flowNodes {
            guard let fills = fills(flow.id) else {
                continue
            }
            guard let drains = drains(flow.id) else {
                continue
            }

            let adjacency = StockAdjacency(id: flow.id, origin: drains, target: fills)

            adjacencies.append(adjacency)
        }
        
        return adjacencies
    }
}
