//
//  SimulationContext.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

import PoieticCore
public struct SimulationContext {
    /// Step number of the simulation.
    ///
    /// Initial step number is 0 - zero.
    ///
    public var step: Int
    
    /// Simulation time in simulation time units.
    ///
    /// Typically for most of the cases the time would be
    /// _step * timeDelta_.
    ///
    public var time: Double
    
    /// Simulation time delta in simulation time units.
    ///
    public var timeDelta: Double
}

// FIXME: [REFACTORING] [SOLVER] REMOVE THIS

public struct SimulatorContext {
    /// Step number of the simulation.
    ///
    /// Initial step number is 0 - zero.
    ///
    public let step: Int
    
    /// Simulation time in simulation time units.
    ///
    /// Typically for most of the cases the time would be
    /// _step * timeDelta_.
    ///
    public let time: Double
    
    /// Simulation time delta in simulation time units.
    ///
    public let timeDelta: Double


    /// Compiled model of the simulation.
    ///
    public let model: CompiledModel
    
    /// Current simulation state.
    ///
    public let state: SimulationState
    
}
