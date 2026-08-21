//
//  SimulationComponents.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore


/// Role in the Stock-Flow simulation.
///
/// Role determines when and how the simulation object is being computed.
///
/// - `stock` – computation defined through formula is done only during initialisation phase
/// - `flow` – computation is performed during initialisation and after stock integration
/// - `auxiliary` – same rule as flow applies
///
/// - **Produced by:** ``ComputationOrderSystem``
/// - **Used by:** ``SimulationPlanningSystem``
///
public enum SimulationRole: Component, Codable {
    /// Computation defined through formula is done only during initialisation phase.
    case stock
    /// Computation is performed during initialisation and after stock integration,
    /// same as auxiliary.
    case flow
    /// Computation is performed during initialisation and after stock integration,
    /// same as flow.
    case auxiliary
}


/// Component with a map from resolved, cleaned and validated names to object IDs.
///
/// - **Created by:** ``NameResolutionSystem``.
/// - **Used by:** ``ParameterConnectionProposalSystem``.
///
public struct SimulationNameLookup: Component {
    public let namedObjects: [String:ObjectID]
}

/// Simulation-facing name of the entity.
///
/// Presence of this component states that the simulation name is valid, unique and non-empty.
/// Source for the simulation object name is usually `name` property of a design object.
///
/// - **Created By**: ``NameResolutionSystem``
///
public struct SimulationName: Component {
    // TODO: Move to Core (start building simulation core)
    // Note: This is a place to keep fully qualified names in the future, for example when we allow model module nesting.
    public let name: String
}


/// Component describing dependencies between stocks and flow rates.
///
/// - SeeAlso: ``StockFlowTopologySystem``, ``FlowRateComponent``.
///
public struct StockComponent: Component {
    /// List of `FlowRate` nodes that fill the stock.
    public let inflowRates: [ObjectID]

    /// List of `FlowRate` nodes that drain the stock.
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
/// - SeeAlso: ``StockFlowTopologySystem``, ``StockComponent``
/// 
public struct FlowRateComponent: Component {
    /// ID of a stock that the flow drains. If nil, then infinite stock (cloud) is assumed.
    ///
    /// The situation:
    ///
    ///     Stock --(Flow)--> Flow Rate
    ///       |                   ^
    ///       |                   +--- Node of interest, read from here
    ///       +-- stock being drained
    ///
    public let drainsStock: ObjectID?
    
    /// ID of a stock that the flow fills. If nil, then infinite stock (cloud) is assumed.
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
}
