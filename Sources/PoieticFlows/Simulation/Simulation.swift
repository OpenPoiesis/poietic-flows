//
//  Simulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

import PoieticCore

// TODO: Move this to Core

public struct SimulationError: Error {
    let objectID: ObjectID
    let error: any Error
}

/// Error raised during simulation.
///
public enum EvaluationError: Error {
    case valueError(ValueError)
    case functionError(String, FunctionError)
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
    /// Create and initialise a simulation state.
    ///
    /// - Parameters:
    ///     - step: The initial step number of the simulation.
    ///     - time: Initial time.
    ///     - timeDelta: Time delta between simulation steps.
    ///
    /// This function creates and computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter.
    ///
    /// - Returns: Newly initialised simulation state.
    ///
    func initialize(time: Double, timeDelta: Double, override: [ObjectID:Variant])  throws (SimulationError) -> SimulationState

    /// Function that updates a simulation state.
    ///
    /// - SeeAlso: ``Simulator/initializeState(time:override:)``,
    ///   ``Simulator/updateBuiltins(_:)````
    ///
    func update(_ state: inout SimulationState) throws (SimulationError)

}

extension Simulation {
    /// Evaluates an arithmetic expression within a simulation state.
    ///
    /// - Returns: Result of the evaluation.
    ///
    public func evaluate(expression: BoundExpression,
                         with state: SimulationState) throws (EvaluationError) -> Variant {
        switch expression {
        case let .value(value):
            return value
            
        case let .binary(op, left, right):
            let leftValue = try evaluate(expression: left, with: state)
            let rightValue = try evaluate(expression: right, with: state)
            
            do {
                return try op.apply([leftValue, rightValue])
            }
            catch {
                throw .functionError(op.name, error)
            }
            
        case let .unary(op, operand):
            let opValue = try evaluate(expression: operand, with: state)
            do {
                return try op.apply([opValue])
            }
            catch {
                throw .functionError(op.name, error)
            }
        
        case let .function(function, arguments):
            let argValues = try arguments.map { expr throws (EvaluationError) in
                try evaluate(expression: expr, with: state)
            }
            do {
                return try function.apply(argValues)
            }
            catch {
                throw .functionError(function.name, error)
            }
            
        case let .variable(variable):
            return state[variable.index]
        }
    }
}
