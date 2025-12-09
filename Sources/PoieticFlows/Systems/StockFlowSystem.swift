//
//  StocksSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 01/11/2025.
//


import PoieticCore

/// System that collects all flow rates and determines their inflows and outflows.
///
/// - **Input:** Nodes of type ``ObjectType/FlowRate``,
/// - **Output:** Set ``FlowRateComponent`` for each flow rate node.
/// - **Forgiveness:** If multiple ``ObjectType/Flow`` edges exist, only one is picked arbitrarily.
///
public struct FlowCollectorSystem: System {

    public init() {}

    public func update(_ frame: AugmentedFrame) throws (InternalSystemError) {
        for flow in frame.filter(type: .FlowRate) {
            // We assume the frame edge reqThank uirements were satisfied, therefore there is most one edge of each
            let fills: ObjectID? = frame.outgoing(flow.objectID).first {
                $0.object.type === ObjectType.Flow
            }?.target
            
            let drains: ObjectID? = frame.incoming(flow.objectID).first {
                $0.object.type === ObjectType.Flow
            }?.origin
            
            let priority: Int = flow["priority", default: 0]
            
            let component = FlowRateComponent(drainsStock: drains,
                                              fillsStock: fills,
                                              priority: priority)
            frame.setComponent(component, for: .object(flow.objectID))
        }
    }
}

/// System that collects all stocks and determines their dependent relationships.
///
/// - **Dependency:** Must run after ``FlowCollectorSystem`` to get the ``FlowRateComponent``.
/// - **Input:** Nodes of type ``ObjectType/Stock``, Flow rates with ``FlowRateComponent``.
/// - **Output:** ``StockDependencyComponent`` set to each stock.
/// - **Forgiveness:** Flow rates without computed component are ignored.
///
struct StockDependencySystem: System {
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(FlowCollectorSystem.self)
    ]
    
    func update(_ frame: AugmentedFrame) throws (InternalSystemError) {
        var filledByRate: [ObjectID:[ObjectID]] = [:] // Flows filling a stock
        var drainedByRate: [ObjectID:[ObjectID]] = [:] // Flows draining a stock

        // Key: stock being filled, value: Stocks being drained.
        // Flows go from "value" to "key"
        var inflowStocks: [ObjectID:[ObjectID]] = [:] // [filled stock: [from drained stock]]
        // Key: stock being drained, value: Stocks being filled.
        // Flows go from "key" to "value"
        var outflowStocks: [ObjectID:[ObjectID]] = [:] // [drained stock:[to filling stock]]

        for flow in frame.filter(type: .FlowRate) {
            guard let component: FlowRateComponent = frame.component(for: .object(flow.objectID)) else {
                continue
            }
            if let stockID = component.fillsStock {
                filledByRate[stockID, default: []].append(flow.objectID)
            }
            if let stockID = component.drainsStock {
                drainedByRate[stockID, default: []].append(flow.objectID)
            }
            if let drainedID = component.drainsStock,
               let filledID = component.fillsStock
            {
                inflowStocks[filledID, default: []].append(drainedID)
                outflowStocks[drainedID, default: []].append(filledID)
            }
        }
        
        for stock in frame.filter(type: .Stock) {
            let component = StockComponent(
                inflowRates: filledByRate[stock.objectID] ?? [],
                outflowRates: drainedByRate[stock.objectID] ?? [],
                inflowStocks: inflowStocks[stock.objectID] ?? [],
                outflowStocks: outflowStocks[stock.objectID] ?? [],
                allowsNegative: stock["allows_negative", default: false]
            )
            frame.setComponent(component, for: .object(stock.objectID))
        }
    }
}

