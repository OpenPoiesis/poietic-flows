//
//  Compiler+StockFlow.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 18/04/2025.
//
import PoieticCore

extension Compiler {
    func compileFlow(_ flow: ObjectSnapshot, name: String, valueType: ValueType) throws (InternalCompilerError) -> BoundFlow {
        let drains = view.drains(flow.objectID)
        let fills = view.fills(flow.objectID)
        var priority: Int
        if let value = flow["priority"] {
            do {
                priority = try value.intValue()
            }
            catch {
                throw .attributeExpectationFailure(flow.objectID, "priority")
            }
        }
        else {
            priority = 0
        }
        let actualIndex = self.createStateVariable(content: .adjustedResult(flow.objectID),
                                                   valueType: valueType,
                                                   name:  name)
        let boundFlow = BoundFlow(objectID: flow.objectID,
                                  estimatedValueIndex: objectVariableIndex[flow.objectID]!,
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
            flowIndices[flow.objectID] = index
        }

        for stock in stocks {
            let inflows: [BoundFlow] = flows.filter { $0.fills == stock.objectID }
            let outflows: [BoundFlow] = flows.filter { $0.drains == stock.objectID }
                .sorted { $0.priority < $1.priority }
            
            let inflowIndices = inflows.map { flowIndices[$0.objectID]! }
            let outflowIndices = outflows.map { flowIndices[$0.objectID]! }

            guard let allowsNegative = try? stock["allows_negative"]?.boolValue() else {
                throw .attributeExpectationFailure(stock.objectID, "allows_negative")
            }

            let compiled = BoundStock(
                objectID: stock.objectID,
                variableIndex: objectVariableIndex[stock.objectID]!,
                allowsNegative: allowsNegative,
                inflows: inflowIndices,
                outflows: outflowIndices
            )
            boundStocks.append(compiled)
        }
        
        return boundStocks
    }
    

}
