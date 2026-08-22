//
//  StocksSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 01/11/2025.
//


import PoieticCore

/// System that collects all flow rates and stocks. Then determines relationships between flow
/// rates and stocks, and flows between stocks (skipping the flow rates).
///
/// - **Input:**
///     - Design nodes of object type `FlowRate`.
///     - Design nodes of object type `Stock`.
/// - **Output:**
///     - Set ``FlowRate`` on each flow rate node entity.
///     - Set ``Stock`` on each stock node entity.
/// - **Forgiveness:**
///     - If multiple edges of object type `Flow` exist, only one is picked arbitrarily.
///
public struct StockFlowTopologySystem: System {
    public static func update(_ world: World) throws (InternalSystemError) {
        guard let plane = world.plane else { return }
        
        // Important: Keep the order: flows first, then stocks.
        collectFlowRates(from: plane, in: world)
        collectStocks(from: plane, in: world)
    }
    
    static func collectFlowRates(from plane: DesignPlane, in world: World) {
        for flow in plane.filter(type: .FlowRate) {
            let entity = world.entity(flow.objectID)!
            
            // We assume the plane edge requirements were satisfied,
            // therefore there is at most one edge of each
            let fills: ObjectID? = plane.outgoing(flow.objectID).first {
                $0.object.type === ObjectType.Flow
            }?.target
            
            let drains: ObjectID? = plane.incoming(flow.objectID).first {
                $0.object.type === ObjectType.Flow
            }?.origin
            
            // Not used now (it was, and it might be, keeping as a note here)
            // let priority: Int = flow["priority", default: 0]
            
            let component = FlowRate(drainsStock: drains, fillsStock: fills)
            entity.setComponent(component)
        }
    }
    
    static public func collectStocks(from plane: DesignPlane, in world: World) {
        var filledByRate: [ObjectID:[ObjectID]] = [:] // Flows filling a stock
        var drainedByRate: [ObjectID:[ObjectID]] = [:] // Flows draining a stock

        // Key: stock being filled, value: Stocks being drained.
        // Flows go from "value" to "key"
        var inflowStocks: [ObjectID:[ObjectID]] = [:] // [filled stock: [from drained stock]]
        // Key: stock being drained, value: Stocks being filled.
        // Flows go from "key" to "value"
        var outflowStocks: [ObjectID:[ObjectID]] = [:] // [drained stock:[to filling stock]]

        for flow in plane.filter(type: .FlowRate) {
            let entity = world.entity(flow.objectID)!
            guard let component: FlowRate = entity.component() else {
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
        
        for stock in plane.filter(type: .Stock) {
            let entity = world.entity(stock.objectID)!
            let component = Stock(
                inflowRates: filledByRate[stock.objectID] ?? [],
                outflowRates: drainedByRate[stock.objectID] ?? [],
                inflowStocks: inflowStocks[stock.objectID] ?? [],
                outflowStocks: outflowStocks[stock.objectID] ?? [],
                allowsNegative: stock["allows_negative", default: false]
            )
            entity.setComponent(component)
        }
    }
}

