//
//  SimulationResultBuilder.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 04/09/2026.
//

import PoieticCore

// TODO: Make time the first column

public struct SimulationResultBuilder {
    let plan: SimulationPlan
    var doubleSeries: [[Double]]
    var variantSeries: [[Variant]]
    
    public private(set) var sampleCount: Int = 0
    var variableToSeries: [Int:(type: SeriesType, index: Int)]
    
    enum SeriesType {
        case double
        case variant
    }
    
    public let timeSettings: SimulationTimeSettings
    public let parameters: [VariableReference:Variant]?

    public init(plan: SimulationPlan,
                timeSettings: SimulationTimeSettings,
                parameters: [VariableReference:Variant]? = nil)
    {
        var doubleCount = 0
        var variantCount = 0
        var timeIndex: Int? = nil
        
        self.plan = plan
        self.variableToSeries = [:]
        self.doubleSeries = []
        self.variantSeries = []
        
        for (index, variable) in plan.stateVariables.enumerated() {
            switch variable.reference.type {
            case .builtin, .stock, .flow, .numeric:
                variableToSeries[index] = (.double, doubleCount)
                doubleCount += 1
            case .variant:
                variableToSeries[index] = (.variant, variantCount)
                variantCount += 1
            }
            
            if variable.reference == .builtin(.time) {
                timeIndex = index
            }
        }
        
        precondition(timeIndex != nil)
        
        for _ in 0..<doubleCount {
            doubleSeries.append(Array())
        }
        for _ in 0..<variantCount {
            variantSeries.append(Array())
        }

        // Carry over to result later, not used here
        self.timeSettings = timeSettings
        self.parameters = parameters
    }

    mutating public func append(state: SimulationState) {
        for (index, variable) in plan.stateVariables.enumerated() {
            let collectionIndex = variableToSeries[index]!.index
            
            switch variable.reference {
            case .builtin(let builtin):
                doubleSeries[collectionIndex].append(state.doubleValue(forBuiltin: builtin))
            case .stock(let stock):
                doubleSeries[collectionIndex].append(state.stocks[stock])
            case .flow(let flow):
                doubleSeries[collectionIndex].append(state.flows[flow])
            case .numeric(let numeric):
                doubleSeries[collectionIndex].append(state.numerics[numeric])
            case .variant(let variant):
                variantSeries[collectionIndex].append(state.variants[variant])
            }
        }
        sampleCount += 1
    }
    
    func build() -> SimulationResult {
        var columns: [SimulationResult.Series] = []

        for (index, variable) in plan.stateVariables.enumerated() {
            let (seriesType, collectionIndex) = variableToSeries[index]!

            let data: SimulationResult.SeriesValues
            switch seriesType {
            case .double: data = .double(doubleSeries[collectionIndex])
            case .variant: data = .variant(variantSeries[collectionIndex])
            }
            let item = SimulationResult.Series(reference: variable.reference, data: data)
            columns.append(item)
        }
        
        let result = SimulationResult(plan: self.plan,
                                      series: columns,
                                      timeSettings: self.timeSettings,
                                      parameters: self.parameters)
        return result
    }
    
}
