//
//  Simulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

import PoieticCore

/// Error raised during simulation.
///
public enum SimulationError: Error {
}

/// Protocol for different kinds of simulations.
///
/// Objects conforming to this protocol can be used with the ``Simulator`` to
/// operate on the simulation state.
///
/// Simulation objects manage only simulation-related objects and variables.
///
/// - SeeAlso: ``Simulator``
///
public protocol Simulation {
    // TODO: Throws SimulationError (RuntimeError)
    /// Function that updates a simulation state.
    ///
    /// - SeeAlso: ``Simulator/initializeState(time:override:)``,
    ///   ``Simulator/setBuiltins(_:)````
    ///
    func update(_ state: inout SimulationState) throws
}

extension Simulation {
    // TODO: Throws SimulationError (RuntimeError)
    /// Evaluates an arithmetic expression within a simulation state.
    ///
    /// - Returns: Result of the evaluation.
    ///
    public func evaluate(expression: BoundExpression,
                         with state: SimulationState) throws -> Variant {
        switch expression {
        case let .value(value):
            return value

        case let .binary(op, lhs, rhs):
            return try op.apply([try evaluate(expression: lhs, with: state),
                                 try evaluate(expression: rhs, with: state)])

        case let .unary(op, operand):
            return try op.apply([try evaluate(expression: operand, with: state)])

        case let .function(functionRef, arguments):
            let evaluatedArgs = try arguments.map {
                try evaluate(expression: $0, with: state)
            }
            return try functionRef.apply(evaluatedArgs)

        case let .variable(variable):
            return state[variable.index]
        }
    }
}
