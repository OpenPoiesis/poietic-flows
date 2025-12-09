//
//  SimulationResult.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 17/03/2025.
//

import PoieticCore

public struct SimulationResult: Component {
    public let initialTime: Double
    public let timeDelta: Double
    public var states: [SimulationState]

    public var endTime: Double { initialTime + Double(max(states.count - 1, 0)) * timeDelta }
    
    // TODO: Add sub-steps and grain enum

    //    enum Grain {
    //        case regular /* sample-state */
    //        case sub /* sub-step */
    //    }
    public init(_ states: [SimulationState] = [], initialTime: Double = 0.0, timeDelta: Double = 1.0) {
        self.states = states
        self.initialTime = initialTime
        self.timeDelta = timeDelta
    }
   
    /// Number of states in the result.
    ///
    public var count: Int { states.count }
    
    public subscript(step: Int) -> SimulationState? {
        guard step < states.count else { return nil }
        return states[step]
    }
    
    public mutating func append(_ state: SimulationState) {
        self.states.append(state)
    }
    
    /// Get numeric time series for a state variable at given index.
    ///
    /// - Precondition: Variable at given index in all states is convertible to a float.
    ///
    public func unsafeFloatValueTimeSeries(at index: Int) -> [Double] {
        return states.map { try! $0[index].doubleValue() }
    }
    
    /// Return numeric time series for given object.
    ///
    /// - Precondition: Variable at given index in all states is convertible to a float.
    ///
    public func unsafeTimeSeries(at index: Int) -> RegularTimeSeries {
        let values: [Double] = unsafeFloatValueTimeSeries(at: index)
        
        let series = RegularTimeSeries(data: values, startTime: initialTime, timeDelta: timeDelta)
        return series
    }

    // func numericTimeSeries(index:Int, convert: (Int, Variant) -> Double) -> RegularTimeSeries
    // func numericTimeSeries(index:Int, notConvertibleDefault: Double) -> RegularTimeSeries

}
