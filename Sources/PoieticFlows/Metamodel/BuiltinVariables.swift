//
//  BuiltinVariables.swift
//
//
//  Created by Stefan Urbanek on 10/03/2024.
//

import PoieticCore

/// Builtin variables for the Stock and Flow simulation.
///
/// The enum is used during computation to set value of a builtin variable.
///
public enum BuiltinVariable: Equatable, CaseIterable, CustomStringConvertible {
    case time
    case timeDelta
    case step
//    case initialTime
//    case endTime
    
    public var description: String { self.name }
    
    public static var allNames: [String] {
        self.allCases.map { $0.name }
    }

    public var name: String {
        switch self {
        case .time: "time"
        case .timeDelta: "time_delta"
        case .step: "simulation_step"
        }
    }
    
    public var valueType: ValueType {
        switch self {
        case .time: .double
        case .timeDelta: .double
        case .step: .int
        }
    }
    
    public var info: Variable {
        switch self {
        case .time: Variable.TimeVariable
        case .timeDelta: Variable.TimeDeltaVariable
        case .step: Variable.SimulationStepVariable
        }
    }
}

extension Variable {
    /// Built-in variable reference that represents the simulation time.
    ///
    public static let TimeVariable = Variable(
        name: "time",
        abstract: "Current simulation time"
    )

    /// Built-in variable reference that represents the time delta.
    ///
    public static let TimeDeltaVariable = Variable(
        name: "time_delta",
        abstract: "Simulation time delta - time between discrete steps of the simulation."
    )
    
    /// Built-in variable containing simulation step.
    ///
    public static let SimulationStepVariable = Variable(
        name: "simulation_step",
        valueType: .double,
        abstract: "Simulation step number."
    )

    // TODO: Add 'initial_time'
    // TODO: Add 'final_time'
}
