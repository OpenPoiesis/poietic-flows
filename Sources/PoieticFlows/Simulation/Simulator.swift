//
//  Simulator.swift
//  
//
//  Created by Stefan Urbanek on 25/08/2023.
//

import PoieticCore

/// Parameters of the simulation.
///
public struct SimulationParameters {
    /// Time of the initialisation state of the simulation.
    public var initialTime: Double
    
    /// Advancement of time for each simulation step.
    public var timeDelta: Double

    /// Final simulation time.
    ///
    /// Simulation is run while the simulation is less than ``endTime``.
    public var endTime: Double
    
    /// Create new simulation options.
    ///
    /// - Parameters:
    ///     - initialTime: Time of the initialisation state of the simulation.
    ///     - timeDelta: Advancement of time for each simulation step.
    ///     - endTime: Final simulation time.
    ///
    /// The default ``endTime`` is set to 10.0 (like the `head` UNIX command number of lines).
    /// It is enough for a reasonable default preview.
    ///
    public init(initialTime: Double = 0.0, timeDelta: Double = 1.0, endTime: Double = 10.0) {
        self.initialTime = initialTime
        self.timeDelta = timeDelta
        self.endTime = endTime
    }

    /// Create new simulation parameters from an object.
    ///
    /// The object is expected to be of a ``Trait/Simulation`` type, although any object with
    /// expected attributes can be used.
    ///
    public init(fromObject object: ObjectSnapshot) {
        self.initialTime = object["initial_time", default: 0.0]
        self.timeDelta = object["time_delta", default: 0.0]

        if let endTime: Double = object["end_time"] {
            self.endTime = endTime
        }
        else {
            if let steps: Int = object["steps"] {
                self.endTime = initialTime + Double(steps + 1) * timeDelta
            }
            else {
                let steps = 10
                self.endTime = initialTime + Double(steps + 1) * timeDelta
            }
        }
    }
}

// TODO: Move this class to Core, we are half-way through decoupling.

/// Object for controlling a simulation session.
///
public class Simulator {
    // Simulation state
    public var parameters: SimulationParameters
    public var currentTime: Double = 0.0
    public var currentStep: Int = 0
    public var currentState: SimulationState?
    
    /// Collected data
    public var result: SimulationResult
    
    // TODO: Allow multiple
    public let simulation: Simulation

    // MARK: - Creation
    
    /// Creates and initialises a simulator.
    ///
    /// - Properties:
    ///   - model: Compiled simulation model that describes the computation.
    ///   - solverType: Type of the solver to be used.
    ///
    /// The simulator is initialised by creating a new solver and initialising
    /// simulation values from the ``SimulationPlan/simulationDefaults`` such as
    /// initial time or time delta (_dt_). If the defaults are not provided then
    /// the following values are used:
    ///
    /// - `initialTime = 0.0`
    /// - `timeDelta = 1.0`
    ///
    public init(simulation: Simulation, parameters: SimulationParameters? = nil) {
        self.simulation = simulation
        self.parameters = parameters ?? SimulationParameters()
        self.currentState = nil
        self.result = SimulationResult(initialTime: self.parameters.initialTime,
                                       timeDelta: self.parameters.timeDelta)
    }
    
    // MARK: - State Initialisation

    /// Initialise the computation state.
    ///
    /// - Parameters:
    ///     - `time`: Initial time. This parameter is usually not used, but
    ///     some computations in the model might use it. Default value is 0.0
    ///     - `override`: Dictionary of values to override during initialisation.
    ///     The values of nodes that are present in the dictionary will not be
    ///     evaluated, but the value from the dictionary will be used.
    ///
    /// - Returns: `StateVector` with initialised values.
    ///
    /// - Note: Use only constants in the `override` dictionary. Even-though
    ///   any node value can be provided, in the future only constants will
    ///   be allowed.
    ///
    @discardableResult
    public func initializeState(time: Double? = nil, override: [ObjectID:Double] = [:]) throws -> SimulationState {
        // TODO: Rename to createInitialState()
        currentStep = 0
        currentTime = time ?? parameters.initialTime

        var overrideVariants: [ObjectID:Variant] = [:]
        for (id, value) in override {
            overrideVariants[id] = Variant(value)
        }

        let state = try simulation.initialize(time: currentTime,
                                              timeDelta: parameters.timeDelta,
                                              override: overrideVariants)
        
        self.result = SimulationResult(initialTime: currentTime, timeDelta: parameters.timeDelta)
        self.result.append(state)
        self.currentState = state
        
        return state
    }


    // MARK: - Step
    
    /// Perform one step of the simulation.
    ///
    /// First, step number is increased by one, current time is increased by time
    /// delta, all built-in variables are set to their current values.
    ///
    /// Then simulation updates the state and result is appended to the collection
    /// of simulation outputs.
    ///
    /// Current state is set to the most recently computed state.
    ///
    /// - SeeAlso: ``Simulation/update(_:context:)``
    ///
    public func step() throws {
        guard let currentState else {
            fatalError("Trying to run an uninitialised simulator")
        }
        
        // 1. Advance time and prepare
        // -------------------------------------------------------
        // 2. Computation
        // -------------------------------------------------------
        let result = try simulation.step(currentState)
        currentStep = result.step
        currentTime = result.time
        
        // 3. Finalisation
        // -------------------------------------------------------

        self.result.append(result)
        self.currentState = result
    }
    
    /// Run the simulation for given number of steps.
    ///
    /// Convenience method.
    ///
    public func run(_ steps: Int? = nil) throws {
        var stepCount = 0
        while currentTime < parameters.endTime {
            if let steps, stepCount >= steps {
                break
            }
            try step()
            stepCount += 1
        }
    }
}
