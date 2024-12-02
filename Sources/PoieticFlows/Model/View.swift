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
    
    /// Metamodel that the view uses to find relevant object types.
    public let metamodel: Metamodel

    /// Graph that the view projects.
    ///
    public let frame: ViewedFrame
    
    /// Create a new view on top of a graph.
    ///
    public init(_ frame: ViewedFrame) {
        self.metamodel = frame.design.metamodel
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
    
    public var flowNodes: [DesignObject] {
        frame.filter {
            $0.structure.type == .node
            && $0.type === ObjectType.Flow
        }
    }
    
    // Parameter queries
    // ---------------------------------------------------------------------
    //
    /// Predicate that matches all edges that represent parameter connections.
    ///
    public var parameterEdges: [EdgeObject<DesignObject>] {
        frame.filterEdges { $0.type === ObjectType.Parameter }
    }
    /// A neighbourhood for incoming parameters of a node.
    ///
    /// Focus node is a node where we would like to see nodes that
    /// are parameters for the node of focus.
    ///
    public func incomingParameters(_ nodeID: ObjectID) -> Neighborhood<ViewedFrame> {
        frame.hood(nodeID, direction: .incoming) {
            $0.type === ObjectType.Parameter
        }
    }
    
    // Fills/drains queries
    // ---------------------------------------------------------------------
    //
    /// List of all edges that fill a stocks. It originates in a flow,
    /// and terminates in a stock.
    ///
    public var fillsEdges: [EdgeObject<DesignObject>] {
        frame.filterEdges { $0.type === ObjectType.Fills }
    }
    
    /// Selector for an edge originating in a flow and ending in a stock denoting
    /// which stock the flow fills. There must be only one of such edges
    /// originating in a flow.
    ///
    /// Neighbourhood of stocks around the flow.
    ///
    ///     Flow --(Fills)--> Stock
    ///      ^                  ^
    ///      |                  +--- Neighbourhood (only one)
    ///      |
    ///      *Node of interest*
    ///
    public func fills(_ flowID: ObjectID) -> ObjectID? {
        frame.outgoing(flowID).first {
            $0.type === ObjectType.Fills
        }?.target
    }
    
    /// Selector for edges originating in a flow and ending in a stock denoting
    /// the inflow from multiple flows into a single stock.
    ///
    ///     Flow --(Fills)--> Stock
    ///      ^                  ^
    ///      |                  +--- *Node of interest*
    ///      |
    ///      Neighbourhood (many)
    ///
    public func inflows(_ nodeID: ObjectID) -> Neighborhood<ViewedFrame> {
        frame.hood(nodeID, direction: .incoming) {
            $0.type === ObjectType.Fills
        }
    }
    /// Returns an ID of a node that the flow drains.
    ///
    /// Neighbourhood of stocks around the flow.
    ///
    ///     Stock --(Drains)--> Flow
    ///      ^                    ^
    ///      |                    +--- Node of interest
    ///      |
    ///      Neighbourhood (only one)
    ///
    public func drains(_ flowID: ObjectID) -> ObjectID? {
        frame.incoming(flowID).first {
            $0.type === ObjectType.Drains
        }?.origin
    }
    /// Selector for edges originating in a stock and ending in a flow denoting
    /// the outflow from the stock to multiple flows.
    ///
    ///
    ///     Stock --(Drains)--> Flow
    ///      ^                    ^
    ///      |                    +--- Neighbourhood (many)
    ///      |
    ///      Node of interest
    ///
    ///
    public func outflows(_ nodeID: ObjectID) -> Neighborhood<ViewedFrame> {
        frame.hood(nodeID, direction: .outgoing) {
            $0.type === ObjectType.Drains
        }
    }
    
    /// List of all edges that drain from a stocks. It originates in a
    /// stock and terminates in a flow.
    ///
    public var drainsEdges: [EdgeObject<DesignObject>] {
        frame.filterEdges { $0.type === ObjectType.Drains }
    }
    
    
    /// A list of variable references to their corresponding objects.
    ///
    public func objectVariableReferences(names: [String:ObjectID]) -> [String:StateVariable.Content] {
        var references: [String:StateVariable.Content] = [:]
        for (name, id) in names {
            references[name] = .object(id)
        }
        return references
    }
    
    public func builtinReferences(names: [String:ObjectID]) -> [String:StateVariable.Content] {
        var references: [String:StateVariable.Content] = [:]
        for (name, id) in names {
            references[name] = .object(id)
        }
        return references
    }
    
    /// Information about node parameters.
    ///
    /// The status is provided by the function ``resolveParameters(_:required:)``.
    ///
    public struct ResolvedParameters {
        public let missing: [String]
        public let unused: [EdgeObject<DesignObject>]
    }

    /// Resolve missing and unused parameter connections.
    ///
    /// The Stock and Flow model requires that parameters are connected to the nodes where they are
    /// used. This is a user-oriented requirement.
    ///
    public func resolveParameters(_ nodeID: ObjectID, required: [String]) ->  ResolvedParameters {
        var missing: Set<String> = Set(required)
        var unused: [EdgeObject<DesignObject>] = []
        
        for edge in incomingParameters(nodeID).edges {
            let parameterNode = frame.node(edge.origin)
            guard let parameterName = parameterNode.name else {
                preconditionFailure("Named node expected")
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
    
    /// Return a list of flows that fill a stock.
    ///
    /// Flow fills a stock if there is an edge of type ``/PoieticCore/ObjectType/Fills``
    /// that originates in the flow and ends in the stock.
    ///
    /// - Parameters:
    ///     - stockID: an ID of a node that must be a stock
    ///
    /// - Returns: List of object IDs of flow nodes that fill the
    ///   stock.
    ///
    /// - Precondition: `stockID` must be an ID of a node that is a stock.
    ///
    public func stockInflows(_ stockID: ObjectID) -> [ObjectID] {
        let stockNode = frame.node(stockID)
        // TODO: Do we need to check it here? We assume model is valid.
        precondition(stockNode.type === ObjectType.Stock)
        
        return inflows(stockID).nodes.map { $0.id }
    }
    
    /// Return a list of flows that drain a stock.
    ///
    /// A stock outflows are all flow nodes where there is an edge of type
    /// ``/PoieticCore/ObjectType/Drains`` that originates in the stock and ends in
    /// the flow.
    ///
    /// - Parameters:
    ///     - stockID: an ID of a node that must be a stock
    ///
    /// - Returns: List of object IDs of flow nodes that drain the
    ///   stock.
    ///
    /// - Precondition: `stockID` must be an ID of a node that is a stock.
    ///
    public func stockOutflows(_ stockID: ObjectID) -> [ObjectID] {
        let stockNode = frame.node(stockID)
        // TODO: Do we need to check it here? We assume model is valid.
        precondition(stockNode.type === ObjectType.Stock)
        
        return outflows(stockID).nodes.map { $0.id }
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
