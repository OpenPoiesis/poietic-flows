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
            && ($0.type.hasTrait(Trait.Formula)
                || $0.type.hasTrait(Trait.Auxiliary))
        }
    }
    
    // Parameter queries
    // ---------------------------------------------------------------------
    //
    public func incomingParameterEdges(_ nodeID: ObjectID) -> [EdgeSnapshot<DesignObject>] {
        return frame.incoming(nodeID).filter { $0.object.type === ObjectType.Parameter }

    }
    /// Nodes representing parameters of a given node.
    ///
    public func incomingParameterNodes(_ nodeID: ObjectID) -> [DesignObject] {
        return incomingParameterEdges(nodeID).map { frame[$0.origin] }
    }

    // Fills/drains queries
    // ---------------------------------------------------------------------
    //
    /// List of all edges that fill a stocks. It originates in a flow,
    /// and terminates in a stock.
    ///
    public var flowEdges: [EdgeSnapshot<DesignObject>] {
        frame.filterEdges { $0.object.type === ObjectType.Flow }
    }
    
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

    /// List of all edges that drain from a stocks. It originates in a
    /// stock and terminates in a flow.
    ///
    public var drainsEdges: [EdgeSnapshot<DesignObject>] {
        frame.filterEdges { $0.object.type === ObjectType.Flow }
    }
            
    /// Information about node parameters.
    ///
    /// The status is provided by the function ``resolveParameters(_:required:)``.
    ///
    public struct ResolvedParameters {
        public let missing: [String]
        // TODO: Change to [ObjectID] for edges
        public let unused: [EdgeSnapshot<DesignObject>]
    }

    /// Resolve missing and unused parameter connections.
    ///
    /// The Stock and Flow model requires that parameters are connected to the nodes where they are
    /// used. This is a user-oriented requirement.
    ///
    public func resolveParameters(_ nodeID: ObjectID, required: [String]) ->  ResolvedParameters {
        var missing: Set<String> = Set(required)
        var unused: [EdgeSnapshot<DesignObject>] = []
        
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

            let delayedInflow = try! frame[drains]["delayed_inflow"]!.boolValue()
            
            let adjacency = StockAdjacency(id: flow.id,
                                           origin: drains,
                                           target: fills,
                                           targetHasDelayedInflow: delayedInflow)

            adjacencies.append(adjacency)
        }
        
        return adjacencies
    }
}
