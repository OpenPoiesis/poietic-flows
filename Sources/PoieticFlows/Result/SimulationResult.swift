//
//  SimulationResult.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 17/03/2025.
//

import PoieticCore

public typealias VariableReference = SimulationState.Reference

public struct SimulationResult: Component {
    public struct Series {
        public let reference: VariableReference
        public let data: SeriesValues
    }

    public enum SeriesValues {
        // TODO: Rename to ColumnContent or ColumnValues
        case double([Double])
        case variant([Variant])
        
        public var count: Int {
            switch self {
            case .double(let values): values.count
            case .variant(let values): values.count
            }
        }
    }
    
    public struct Sample {
        public let sampleIndex: Int
        let result: SimulationResult
        public func value(for reference: VariableReference) -> Variant? {
            guard let seriesIndex = result.referenceIndex[reference] else { return nil }
            return result.value(at: sampleIndex, forSeriesAt: seriesIndex)
        }
        public func value(atSeries seriesIndex: Int) -> Variant {
            return result.value(at: sampleIndex, forSeriesAt: seriesIndex)
        }
    }

    
    /// Simulation plan according to which the simulation produced this result.
    ///
    public let plan: SimulationPlan
    
    /// Series of simulation variables.
    ///
    public let series: [Series]
    
    /// Time settings used for simulation
    ///
    public let timeSettings: SimulationTimeSettings
    
    /// Simulation parameters used in simulation that produced this result; included for provenance.
    ///
    public let parameters: [VariableReference:Variant]?
    // TODO: Include other simulation config for provenance. Use [String:Variant] so we can later move result to core, be domain-free

    /// Number of samples in the result.
    ///
    /// The number of samples is usually number of simulation steps + 1 (initial state).
    ///
    public let sampleCount: Int
    private let referenceIndex: [VariableReference:Int]
    
    /// - Precondition: All series must have the same number of values.
    public init(plan: SimulationPlan,
                series: [Series],
                timeSettings: SimulationTimeSettings,
                parameters: [VariableReference:Variant]? = nil)
    {
        self.plan = plan
        self.timeSettings = timeSettings
        
        if series.count > 0 {
            let count = series[0].data.count
            precondition(series.allSatisfy{ $0.data.count == count })
            self.sampleCount = count
        }
        else {
            self.sampleCount = 0
        }
        self.series = series
        
        var map: [VariableReference:Int] = [:]
        for (index, item) in series.enumerated() {
            map[item.reference] = index
        }
        self.referenceIndex = map
        self.parameters = parameters
    }
    
    public func sample(at index: Int) -> Sample {
        return Sample(sampleIndex: index, result: self)
    }
    
    public func seriesIndex(_ reference: VariableReference) -> Int? {
        return referenceIndex[reference]
    }
    /// Get series indices for given variable references.
    ///
    /// - Precondition: Result must contain all variables from the list.
    public func seriesIndices(_ references: [VariableReference]) -> [Int] {
        // TODO: [QUESTION] What should we do on unknown? precondition? I would prefer not to throw here
        var result: [Int] = []
        for ref in references {
            guard let index = referenceIndex[ref]
            else { preconditionFailure("Unknown result variable: \(ref)") }
            result.append(index)
        }
        return result
    }

    public func doubleSeries(at index: Int) -> [Double]? {
        guard case let .double(values) = series[index].data
        else { return nil }

        return values
    }
                                                                                                                                                                                                            
    public func variantSeries(at index: Int) -> [Variant]? {
        guard case let .variant(values) = series[index].data
        else { return nil }
        
        return values
    }
    
    public func seriesValues(at index: Int) -> SeriesValues {
        return series[index].data
    }
    
    public func value(at sampleIndex: Int, forSeriesAt seriesIndex: Int) -> Variant {
        let result: Variant
        
        let data = seriesValues(at: seriesIndex)
        switch data {
        case .double(let values): result = Variant(values[sampleIndex])
        case .variant(let values): result = values[sampleIndex]
        }
        
        return result
    }
    
    public func regularTimeSeries(at index: Int) -> RegularTimeSeries? {
        guard let doubles = doubleSeries(at: index)
        else { return nil }
        
        return RegularTimeSeries(data: doubles,
                                 startTime: timeSettings.startTime,
                                 timeDelta: timeSettings.timeStep)
    }
}
