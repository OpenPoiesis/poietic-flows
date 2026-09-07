//
//  SimulationResultView.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 23/08/2026.
//

import PoieticCore

/// Convenience view on simulation result.
///
/// You can use simulation result view for simple printing of the simulation results.
///
/// ### Example
///
/// ```swift
/// let plan: SimulationPlan     // Assume this exists.
/// let result: SimulationResult // Assume this exists.
///
/// let references = plan.defaultVariables.map { $0.reference }
/// let view = SimulationResultView(result: result, selection: references)
///
/// print(view.columnKeys.joined(separator: "\t"))
/// for row in view {
///     print(row.stringValues().joined(separator: "\t"))
/// }
/// ```
///
/// - Note: This is not suitable for a CSV output. Please use `CSVFormatter` from PoieticCore.
/// 
public struct SimulationResultView {
    public let result: SimulationResult
    
    // TODO: [QUESTION] Should we store references or whole variables?
    public let selection: [VariableReference]
    public let resultSeriesIndices: [Int]
    public var variables: [StateVariable] {
        // We can do compact map
        return selection.compactMap { result.plan.variable(for: $0) }
    }
    
    /// Create a new view for a result and a plan.
    ///
    /// - Parameters:
    ///     - result: Simulation result.
    ///     - selection: List of variable references
    ///
    /// - Precondition: Selection references must exist in the result plan.
    ///
    public init(result: SimulationResult, selection: [VariableReference]? = nil)
    {
        // Validate the selection
        // TODO: Should we fail (caller responsible) or should we keep only existing (and caller checks what we have later)?
        if let selection {
            for ref in selection {
                guard result.plan.variable(for: ref) != nil else {
                    preconditionFailure("Unknown variable: \(ref)")
                }
            }
        }
        
        self.result = result

        if let selection {
            self.selection = selection
        }
        else {
            self.selection = result.plan.stateVariables.map {  $0.reference}
        }
        self.resultSeriesIndices = result.seriesIndices(self.selection)
    }
    
    /// Get number of result states.
    public var sampleCount: Int { result.sampleCount }

    /// Get values at state at given index.
    ///
    public func values(at sampleIndex: Int) -> [Variant]? {
        guard sampleIndex >= 0 && sampleIndex < result.sampleCount
        else { return nil }

        let values = resultSeriesIndices.map {
            result.value(at: sampleIndex, forSeriesAt: $0)
        }

        return values
    }
}

extension SimulationResultView: Sequence {
    public typealias Iterator = SimulationResultViewIterator
    public typealias Element = Sample
    
    public struct SimulationResultViewIterator: IteratorProtocol {
        let view: SimulationResultView
        var index: Int
        init(view: SimulationResultView) {
            self.view = view
            self.index = 0
        }
        
        public mutating func next() -> Sample? {
            guard index < view.sampleCount else { return nil }
            let sample = Sample(sampleIndex: index, view: view)
            index += 1
            return sample
        }
    }
    
    public struct Sample {
        public let sampleIndex: Int
        let view: SimulationResultView
        public var values: [Variant] {
            // We can force unwrap because we checked the index in the iterator
            view.values(at: sampleIndex)!
        }
        
        /// Get the row as text by converting each value to a string.
        ///
        /// Columns that cannot be converted to string are presented as empty string.
        ///
        /// - Note: This is a convenience method with default value formatting. For proper
        ///   display, the caller is recommended to do the formatting of ``values`` instead.
        ///
        public func stringValues() -> [String] {
            let stringValues: [String] = values.map {
                (try? $0.stringValue()) ?? ""
            }
            return stringValues
        }
    }

    public func makeIterator() -> SimulationResultViewIterator {
        return SimulationResultViewIterator(view: self)
    }
}
