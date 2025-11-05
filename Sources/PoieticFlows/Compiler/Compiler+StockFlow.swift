//
//  Compiler+StockFlow.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 18/04/2025.
//
import PoieticCore
#if false // Disabled during refactoring.

extension OLD_Compiler {
    func compileFlow(_ flow: ObjectSnapshot, name: String, valueType: ValueType, context: CompilationContext) throws (InternalCompilerError) -> BoundFlow {
        let drains = context.view.drains(flow.objectID)
        let fills = context.view.fills(flow.objectID)
        let priority: Int = flow["priority", default: 0]
        let actualIndex = createStateVariable(content: .adjustedResult(flow.objectID),
                                              valueType: valueType,
                                              name:  name,
                                              context: context)
        let boundFlow = BoundFlow(objectID: flow.objectID,
                                  estimatedValueIndex: context.objectVariableIndex[flow.objectID]!,
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
    func compileStocks(_ context: CompilationContext) throws (InternalCompilerError) -> [BoundStock] {
        var boundStocks: [BoundStock] = []

        let stocks = context.frame.filter(type: .Stock)
        var flowIndices: [ObjectID: Int] = [:]
        for (index, flow) in context.flows.enumerated() {
            flowIndices[flow.objectID] = index
        }

        for stock in stocks {
            let inflows: [BoundFlow] = context.flows.filter { $0.fills == stock.objectID }
            let outflows: [BoundFlow] = context.flows.filter { $0.drains == stock.objectID }
                .sorted { $0.priority < $1.priority }
            
            let inflowIndices = inflows.map { flowIndices[$0.objectID]! }
            let outflowIndices = outflows.map { flowIndices[$0.objectID]! }

            guard let allowsNegative: Bool = stock["allows_negative"] else {
                throw .attributeExpectationFailure(stock.objectID, "allows_negative")
            }

            let compiled = BoundStock(
                objectID: stock.objectID,
                variableIndex: context.objectVariableIndex[stock.objectID]!,
                allowsNegative: allowsNegative,
                inflows: inflowIndices,
                outflows: outflowIndices
            )
            boundStocks.append(compiled)
        }
        
        return boundStocks
    }
    

}
#endif
