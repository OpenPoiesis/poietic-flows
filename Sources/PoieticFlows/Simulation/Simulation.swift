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

public protocol Simulation {
    // TODO: Throws SimulationError (RuntimeError)
    func update(_ state: inout SimulationState, context: SimulationContext) throws
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
