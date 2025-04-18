//
//  Compiler+StockFlow.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 18/04/2025.
//
import PoieticCore

extension Compiler {
    
    
    func compileFlows() throws (InternalCompilerError) -> [BoundFlow] {
        var boundFlows: [BoundFlow] = []

        let flowNodes: [DesignObject] = frame.filter {
                $0.structure.type == .node
                && $0.type === ObjectType.FlowRate
            }

        for flow in flowNodes {
            let drains = view.drains(flow.id)
            let fills = view.fills(flow.id)
            guard let priority = try? flow["priority"]?.intValue() else {
                throw .attributeExpectationFailure(flow.id, "priority")
            }
            let boundFlow = BoundFlow(id: flow.id,
                                      variableIndex: objectVariableIndex[flow.id]!,
                                      priority: priority,
                                      drains: drains,
                                      fills: fills)

            boundFlows.append(boundFlow)
        }
        
        return boundFlows
    }
    
    /// Compile all stock nodes.
    ///
    /// The function extracts component from the stock that is necessary
    /// for simulation. Then the function collects all inflows and outflows
    /// of the stock.
    ///
    /// - Returns: Extracted and derived stock node information.
    ///
    func compileStocksAndFlows() throws (InternalCompilerError) -> ([BoundStock], [BoundFlow]) {
        var boundStocks: [BoundStock] = []

        let stocks = frame.filter(type: .Stock)
        let boundFlows: [BoundFlow] = try compileFlows()

        var outflows: [ObjectID: [BoundFlow]] = [:]
        var inflows: [ObjectID: [BoundFlow]] = [:]
        
        
        for flow in boundFlows {
            if let drains = flow.drains {
                outflows[drains, default: []].append(flow)
            }
            if let fills = flow.fills {
                inflows[fills, default: []].append(flow)
            }
        }
        
        for stock in stocks {
            if let unsorted = outflows[stock.id] {
                outflows[stock.id] = unsorted.sorted { $0.priority < $1.priority }
            }
            else {
                outflows[stock.id] = []
            }

            let inflowIndices = inflows[stock.id]?.map { $0.variableIndex } ?? []
            let outflowIndices = outflows[stock.id]?.map { $0.variableIndex } ?? []
            
            guard let allowsNegative = try? stock["allows_negative"]?.boolValue() else {
                throw .attributeExpectationFailure(stock.id, "allows_negative")
            }

            let compiled = BoundStock(
                id: stock.id,
                variableIndex: objectVariableIndex[stock.id]!,
                allowsNegative: allowsNegative,
                inflows: inflowIndices,
                outflows: outflowIndices
            )
            boundStocks.append(compiled)
        }
        
        return (boundStocks, boundFlows)
    }
    

}
