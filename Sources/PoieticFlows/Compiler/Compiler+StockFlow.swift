//
//  Compiler+StockFlow.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 18/04/2025.
//
import PoieticCore

extension Compiler {
    func compileFlow(_ flow: DesignObject, name: String, valueType: ValueType) throws (InternalCompilerError) -> BoundFlow {
        let drains = view.drains(flow.id)
        let fills = view.fills(flow.id)
        var priority: Int
        if let value = flow["priority"] {
            do {
                priority = try value.intValue()
            }
            catch {
                throw .attributeExpectationFailure(flow.id, "priority")
            }
        }
        else {
            priority = 0
        }
        let actualIndex = self.createStateVariable(content: .adjustedResult(flow.id),
                                                   valueType: valueType,
                                                   name:  name)
        let boundFlow = BoundFlow(id: flow.id,
                                  estimatedValueIndex: objectVariableIndex[flow.id]!,
                                  adjustedValueIndex: actualIndex,
                                  priority: priority,
                                  drains: drains,
                                  fills: fills)

        return boundFlow
    }
        
    /// Compile all stock nodes.
    ///
    /// The function extracts component from the stock that is necessary
    /// for simulation. Then the function collects all inflows and outflows
    /// of the stock.
    ///
    /// - Returns: Extracted and derived stock node information.
    ///
    func compileStocks() throws (InternalCompilerError) -> [BoundStock] {
        var boundStocks: [BoundStock] = []

        let stocks = frame.filter(type: .Stock)
        var flowIndices: [ObjectID: Int] = [:]
        for (index, flow) in flows.enumerated() {
            flowIndices[flow.id] = index
        }

        for stock in stocks {
            let inflows: [BoundFlow] = flows.filter { $0.fills == stock.id }
            let outflows: [BoundFlow] = flows.filter { $0.drains == stock.id }
                .sorted { $0.priority < $1.priority }
            
            let inflowIndices = inflows.map { flowIndices[$0.id]! }
            let outflowIndices = outflows.map { flowIndices[$0.id]! }

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
        
        return boundStocks
    }
    

}
