//
//  SimulationResultView.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 23/08/2026.
//

import PoieticCore

public enum VariableNameFormat: CaseIterable {
    case normalized
    case display
}

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
/// let view = SimulationResultView(result: result, plan: plan, variables: plan.defaultVariables)
///
/// print(view.columnNames.joined(separator: "\t"))
/// for row in view {
///     print(row.stringValues().joined(separator: "\t"))
/// }
/// ```
///
/// - Note: This is not suitable for a CSV output. Please use `CSVFormatter` from PoieticCore.
/// 
public struct SimulationResultView {
    public let result: SimulationResult
    public let plan: SimulationPlan
    public let columnKeys: [String]
    let variableIndices: [Int]
    public let keyToColumn: [String:Int]
    
    // TODO: Not sure if this is the right place (and name) for this
    public static func header(variables: [StateVariable],
                              format: VariableNameFormat,
                              in world: World) -> [String]
    {
        var header: [String] = []
        for variable in variables {
            let item: String
            switch format {
            case .normalized: item = variable.nameKey
            case .display:
                if let objectID = variable.objectID,
                   let entity = world.entity(objectID),
                   let normalized: NormalizedName = entity.component()
                {
                    item = normalized.displayName
                }
                else if case let .builtin(builtin) = variable.content {
                    item = builtin.name
                }
                else {
                    item = variable.nameKey
                }
            }
            header.append(item)
        }
        return header
    }
    
    /// Create a new view for a result and a plan.
    ///
    /// - Parameters:
    ///     - result: Simulation result.
    ///     - plan: Simulation plan for resolving variables in the result.
    ///     - columns: List of variable names the view will use. Variables that do not
    ///       exist in the plan will be skipped. If `nil` is given, then all
    ///       variables from the plan are used.
    ///
    public init(result: SimulationResult,
                plan: SimulationPlan,
                columns: [String]? = nil)
    {
        self.result = result
        self.plan = plan
        
        var variables: [StateVariable] = []
        if let columns {
            for name in columns {
                let key = NormalizedName.normalize(name)
                guard let variable = plan.variable(withKey: key) else { continue }
                variables.append(variable)
            }
        }
        else {
            variables = plan.stateVariables
        }
        
        self.columnKeys = variables.map { $0.nameKey }
        self.variableIndices = variables.map { $0.index }
        var map: [String:Int] = [:]
        for (i, name) in columnKeys.enumerated() {
            map[name] = i
        }
        self.keyToColumn = map
    }
    
    public init(result: SimulationResult, plan: SimulationPlan, variables: [StateVariable]) {
        self.result = result
        self.plan = plan
        
        self.columnKeys = variables.map { $0.nameKey }
        self.variableIndices = variables.map { $0.index }
        var map: [String:Int] = [:]
        for (i, name) in columnKeys.enumerated() {
            map[name] = i
        }
        self.keyToColumn = map
    }

    /// Get number of result states.
    public var count: Int { result.states.count }

    public func header(format: VariableNameFormat, in world: World) -> [String] {
        let variables = self.variableIndices.map { self.plan.stateVariables[$0] }
        return Self.header(variables: variables, format: format, in: world)
    }

    /// Get values at state at given index.
    ///
    public func values(at index: Int) -> [Variant]? {
        guard index >= 0 && index < result.states.count
        else { return nil }
        let state = result.states[index]
        return variableIndices.map { state.values[$0] }
    }
}

extension SimulationResultView: Sequence {
    public typealias Iterator = SimulationResultViewIterator
    public typealias Element = Row
    
    public struct SimulationResultViewIterator: IteratorProtocol {
        let view: SimulationResultView
        var index: Int
        init(view: SimulationResultView) {
            self.view = view
            self.index = 0
        }
        
        public mutating func next() -> Row? {
            guard index < view.count else { return nil }
            let row = Row(index: index, view: view)
            index += 1
            return row
        }
    }
    
    public struct Row {
        public let index: Int
        let view: SimulationResultView
        public var values: [Variant] {
            // We can force unwrap because we checked the index in the iterator
            view.values(at: index)!
        }
        
        public subscript(columnKey: String) -> Variant? {
            guard let index = view.keyToColumn[columnKey] else { return nil }
            return values[index]
        }
        
        /// Get the row as text by converting each value to a string.
        ///
        /// Columns that cannot be converted to string are presented as empty string.
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
