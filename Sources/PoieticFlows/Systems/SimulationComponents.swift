//
//  SimulationComponents.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore

/// Component with a list of simulation objects in order of their computational dependency.
///
/// The computational dependency is determined by flow and parameters edges in the design graph.
///
/// - **Produced by:** ``SimulationOrderDependencySystem``
///
public struct SimulationOrderComponent: Component {
    internal init(objects: [ObjectSnapshot] = [], stocks: [ObjectID] = [], flows: [ObjectID] = []) {
        self.objects = objects
        self.stocks = stocks
        self.flows = flows
    }
    
    // TODO: Rename to orderedObjects
    /// List of simulation objects in order of their computational dependency.
    ///
    let objects: [ObjectSnapshot]
    // TODO: Documentation
    // Used also for verification whether we got all right
    /// List of object IDs representing stocks, in order of computational dependency within the
    /// whole graph.
    let stocks: [ObjectID]

    /// List of object IDs representing flows, in order of computational dependency within the
    /// whole graph.
    let flows: [ObjectID]
}

/// Component containing derived details required for Stock and Flow simulation.
///
/// Objects that have no role component are not considered for simulation.
///
/// Why the role is not part of the metamodel: The design object model is generic, not
/// stock-and-flow specific. There might be components deciding and deriving information that
/// can incorporate variety of object types into the simulation. However, computational perspective
/// we recognise only three roles of nodes: stocks, flows and auxiliaries.
///
/// - **Produced by:** ``SimulationOrderDependencySystem``
///
public struct SimulationRoleComponent: Component {
    var role: SimulationObject.Role
}
public struct SimulationNameLookupComponent: Component {
    let namedObjects: [String:ObjectID]
}

/// Name of an object by which the object can be referred to within the simulation.
///
/// Only objects where the name is relevant to the simulation have this component.
///
public struct SimulationObjectNameComponent: Component {
    let name: String
}


// TODO: Rename to just StockComponent
/// Component describing dependencies between stocks and flow rates.
///
/// - SeeAlso: ``StockDependencySystem``, ``FlowCollectorSystem``.
///
public struct StockComponent: Component {
    /// List of ``ObjectType/FlowRate`` nodes that fill the stock.
    public let inflowRates: [ObjectID]

    /// List of ``ObjectType/FlowRate`` nodes that drain the stock.
    public let outflowRates: [ObjectID]

    /// List of stocks that are drained.
    public let inflowStocks: [ObjectID]
    
    /// List of stocks that are filled.
    public let outflowStocks: [ObjectID]
    
    public let allowsNegative: Bool
}

/// Component with information about flow rate between two stocks.
///
/// Situation:
///
///     Stock --(Flow)--> FlowRate --(Flow)--> Stock
///      ^                    ^                  ^
///      |                    |                  |
///      |             Node of component         +--- stock that the flow rate node fills
///      |
///     Stock that the flow rate node drains
///
public struct FlowRateComponent: Component {
    /// ID of a stock that the flow drains. If nil, then infinite stock is assumed.
    ///
    /// The situation:
    ///
    ///     Stock --(Flow)--> Flow Rate
    ///       |                   ^
    ///       |                   +--- Node of interest, read from here
    ///       +-- stock being drained
    ///
    public let drainsStock: ObjectID?
    
    /// ID of a stock that the flow fills. If nil, then infinite stock is assumed.
    ///
    /// The situation:
    ///
    ///     FlowRate --(Flow)--> Stock
    ///      ^                     ^
    ///      |                     +--- stock that the flow fills
    ///      |
    ///     Node of interest
    ///
    public let fillsStock: ObjectID?

    /// Priority when sorting flow rates.
    public let priority: Int
}

extension SimulationPlan: Component {
}
