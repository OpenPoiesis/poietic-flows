//
//  Simulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

import PoieticCore

// TODO: Deprecate the protocol(?)

public struct SimulationError: Error {
    let objectID: ObjectID
    let error: any Error
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
    ///     - time: Initial time.
    ///     - timeDelta: Time delta between simulation steps.
    ///     - parameters: Initial parameters that override computed values.
    ///
    /// This function creates and computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter.
    ///
    /// - Returns: Newly initialised simulation state.
    ///
    func initialize(time: Double, timeDelta: Double, parameters: [ObjectID:Variant]) throws (SimulationError) -> SimulationState

    /// Function that updates a simulation state.
    ///
    /// - SeeAlso: ``Simulator/initializeState(time:override:)``,
    ///   ``Simulator/updateBuiltins(_:)````
    ///
    func step(_ state: SimulationState) throws (SimulationError) -> SimulationState

}

