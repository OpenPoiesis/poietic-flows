//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 10/03/2024.
//

import PoieticCore

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
