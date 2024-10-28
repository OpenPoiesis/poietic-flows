//
//  Simulator.swift
//  
//
//  Created by Stefan Urbanek on 25/08/2023.
//

import PoieticCore

/// Object for controlling a simulation session.
///
public class Simulator {
    public protocol Delegate {
        func simulatorDidInitialize(_ simulator: Simulator, context: SimulatorContext)
        func simulatorDidStep(_ simulator: Simulator, context: SimulatorContext)
        func simulatorDidRun(_ simulator: Simulator, context: SimulatorContext)
    }

    public static let BuiltinVariables: [Variable] = [
        Variable.TimeVariable,
        Variable.TimeDeltaVariable,
    ]

    var delegate: Delegate?
    
    // Simulation parameters

    /// Initial time of the simulation.
    public var initialTime: Double
    
    /// Time between simulation steps.
    public var timeDelta: Double
    
    // MARK: - Simulator state
    
    /// Current simulation step
    public var currentStep: Int = 0
    public var currentTime: Double = 0
    // TODO: Make currentState non-optional
    public var currentState: SimulationState!
    public var compiledModel: CompiledModel
    
    /// Collected data
    /// TODO: Make this an object, so we can derive more info
    public var output: [SimulationState]
    
    // TODO: Allow multiple
    public let  simulation: Simulation
    // MARK: - Creation
    
    /// Creates and initialises a simulator.
    ///
    /// - Properties:
    ///   - model: Compiled simulation model that describes the computation.
    ///   - solverType: Type of the solver to be used.
    ///
    /// The simulator is initialised by creating a new solver and initialising
    /// simulation values from the ``CompiledModel/simulationDefaults`` such as
    /// initial time or time delta (_dt_). If the defaults are not provided then
    /// the following values are used:
    ///
    /// - `initialTime = 0.0`
    /// - `timeDelta = 1.0`
    ///
    public init(_ model: CompiledModel, simulation: Simulation? = nil) {
        self.compiledModel = model
        self.currentState = nil
        self.simulation = simulation ?? StockFlowSimulation(model)
        
        if let defaults = model.simulationDefaults {
            self.initialTime = defaults.initialTime
            self.timeDelta = defaults.timeDelta
        }
        else {
            self.initialTime = 0.0
            self.timeDelta = 1.0
        }
        
        output = []
    }

    // MARK: - State Initialisation

    // FIXME: [REFACTORING] [SOLVER] MERGE THE FOLLOWING DOC
    /// Initialise the simulation state with existing frame.
    ///
    /// vvvv TODO TODO TODO MERGE THIS WITH THE FOLLOWING
    ///
    /// The initialisation process:
    /// - The current time is set to ``initialTime``.
    /// - All output is cleared.
    /// - Initial state is created and added to the output.
    ///
    /// If a delegate is set, then delegate's
    /// ``Delegate/simulatorDidInitialize(_:context:)`` is called.
    ///
    /// - Parameters:
    ///     - override: Computed values to override. The keys are computed
    ///       node IDs and dictionary values are values to be used instead
    ///       the ones specified in the original nodes.
    ///
    /// - Returns: Initial state.
    ///
    // FIXME: [REFACTORING] [SOLVER] MERGE THE FOLLOWING DOC

    /// ^^^^
    /// Initialise the computation state.
    ///
    /// - Parameters:
    ///     - `time`: Initial time. This parameter is usually not used, but
    ///     some computations in the model might use it. Default value is 0.0
    ///     - `override`: Dictionary of values to override during initialisation.
    ///     The values of nodes that are present in the dictionary will not be
    ///     evaluated, but the value from the dictionary will be used.
    ///
    /// This function computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter.
    ///
    /// - Returns: `StateVector` with initialised values.
    ///
    /// - Precondition: The compiled model must be valid. If the model
    ///   is not valid and contains elements that can not be computed
    ///   correctly, such as invalid variable references, this function
    ///   will fail.
    ///
    /// - Note: Use only constants in the `override` dictionary. Even-though
    ///   any node value can be provided, in the future only constants will
    ///   be allowed.
    ///
    /// - Note: Values for stocks in the `override` dictionary will be used
    ///   only during initialisation.
    ///
    @discardableResult
    public func initializeState(time: Double? = nil, override: [ObjectID:Double] = [:]) throws -> SimulationState {
        currentStep = 0

        if let defaults = compiledModel.simulationDefaults {
            self.initialTime = time ?? defaults.initialTime
            self.timeDelta = defaults.timeDelta
        }
        else {
            self.initialTime = time ?? 0.0
            self.timeDelta = 1.0
        }

        currentTime = initialTime

        let simulation = StockFlowSimulation(compiledModel)
        var state = SimulationState(model: compiledModel)
        setBuiltins(&state)

        try simulation.initialize(&state)
        
        for (id, value) in override {
            guard let index = compiledModel.variableIndex(of: id) else {
                // TODO: Should we complain?
                continue
            }
            state[index] = Variant(value)
        }
        
        output.removeAll()
        output.append(state)
        self.currentState = state
        
        let context = SimulatorContext(
            step: currentStep,
            time: currentTime,
            timeDelta: timeDelta,
            model: compiledModel,
            state: currentState!)

        delegate?.simulatorDidInitialize(self, context: context)

        return state
    }


    /// Set values of built-in variables such as time or time delta.
    ///
    /// - SeeAlso: ``CompiledModel/builtins``
    ///
    public func setBuiltins(_ state: inout SimulationState) {
        for variable in compiledModel.builtins {
            let value: Variant

            switch variable.builtin {
            case .time:
                value = Variant(currentTime)
            case .timeDelta:
                value = Variant(timeDelta)
            }
            state[variable.variableIndex] = value
        }
    }

    // MARK: - Step
    
    /// Perform one step of the simulation.
    ///
    /// - Precondition: Frame and model must exist.
    ///
    public func step() throws {
        guard let currentState else {
            fatalError("Trying to run an uninitialised simulator")
        }
        
        // 1. Preparation
        // -------------------------------------------------------
        currentStep += 1
        currentTime += timeDelta
        
        var result = currentState
        setBuiltins(&result)
        
        // 2. Computation
        // -------------------------------------------------------
        let context = SimulationContext(
            step: currentStep,
            time: currentTime,
            timeDelta: timeDelta
        )
        
        try simulation.update(&result, context: context)

        // 3. Finalisation
        // -------------------------------------------------------

        output.append(result)
        self.currentState = result
    }
    
    /// Run the simulation for given number of steps.
    ///
    public func run(_ steps: Int) throws {
        // TODO: Add step function (SimulationState, SimulationContext) -> Void or Bool for halt
        for _ in (1...steps) {
            try step()
        }
    }

    /// Get data series for computed variable at given index.
    ///
    public func dataSeries(index: Int) -> [Double] {
        return output.map { try! $0[index].doubleValue() }
    }
    
    /// Get series of time points.
    ///
    /// - SeeAlso: ``CompiledModel/timeVariableIndex``
    ///
    public var timePoints: [Double] {
        // TODO: We need a cleaner way how to get this.
        return output.map {
            try! $0[compiledModel.timeVariableIndex].doubleValue()
        }
    }
}
