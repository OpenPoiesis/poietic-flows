//
//  StockFlowSimulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

// FIXME: [IMPORTANT] Test for dt = 0
// TODO: Halt on negative inflow or outflow (optional)

import PoieticCore

/// Stock-Flow simulation specific computation and logic.
///
public class StockFlowSimulation: Simulation {
    /// Simulation plan according which the computation is performed.
    ///
    public let plan: SimulationPlan
    
    public enum FlowScaling: String, RawRepresentable, CaseIterable {
        case inflowFirst
        case outflowFirst
        // case balanced
    }
    
    public enum SolverType: String, RawRepresentable, CaseIterable {
        case euler
        case rk4
    }
    
    /// Type of a solver to be used for the simulation.
    public var solver: SolverType
    public var flowScaling: FlowScaling

    /// Create a new Stock Flow simulation for a specific model.
    ///
    public init(_ plan: SimulationPlan, solver: SolverType = .euler, flowScaling: FlowScaling = .outflowFirst) {
        self.plan = plan
        self.solver = solver
        self.flowScaling = flowScaling
    }
   
    // MARK: - Initialization
    /// Create and initialise a simulation state.
    ///
    /// - Parameters:
    ///     - step: The initial step number of the simulation.
    ///     - time: Initial time.
    ///     - timeDelta: Time delta between simulation steps.
    ///     - override: Dictionary of values to override during initialisation.
    ///
    /// This function creates and computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter.
    ///
    /// When the ``override`` parameter is specified, then values for objects with given
    /// ID will be used from the dictionary instead of being computed.
    ///
    /// - Returns: Newly initialised simulation state.
    ///
    public func initialize(time: Double=0,
                           timeDelta: Double=1.0,
                           parameters: [ObjectID:Variant]=[:])
    throws (SimulationError) -> SimulationState
    {
        var state = SimulationState(count: plan.stateVariables.count,
                                    step: 0,
                                    time: time,
                                    timeDelta: timeDelta)

        setBuiltins(in: &state)

        for (index, simObject) in plan.simulationObjects.enumerated() {
            if let value = parameters[simObject.objectID] {
                state[simObject.variableIndex] = value
            }
            else {
                try initialize(objectAt: index, in: &state)
            }
        }

        return state
    }
    
    /// Set values of built-in variables such as time or time delta.
    ///
    /// - SeeAlso: ``SimulationPlan/builtins``, ``BoundBuiltins``
    ///
    public func setBuiltins(in state: inout SimulationState) {
        state[plan.builtins.time] = Variant(state.time)
        state[plan.builtins.timeDelta] = Variant(state.timeDelta)
        state[plan.builtins.step] = Variant(state.step)
    }

    /// Initialise an object in a given state.
    ///
    /// - Parameters:
    ///     - index: Index of the object to be evaluated.
    ///     - state: simulation state within which the expression is evaluated
    ///
    public func initialize(objectAt index: Int, in state: inout SimulationState) throws (SimulationError) {
        let object = plan.simulationObjects[index]
        let result: Variant
       
        do {
            switch object.computation {
            case let .formula(expression):
                result = try evaluate(expression: expression, with: state)
            case let .graphicalFunction(function):
                result = try evaluate(graphicalFunction: function, with: state)
            case let .delay(delay):
                result = try initialize(delay: delay, in: &state)
            case let .smooth(smooth):
                result = initialize(smooth: smooth, in: &state)
            }
        }
        catch {
            throw SimulationError(objectID: object.objectID, error: error)
        }
        state[object.variableIndex] = result
    }

    /// Initialise a simulated delay.
    ///
    /// The function prepares internal state variable holding a delay queue and returns
    /// an initial value of the delay node.
    ///
    /// - Parameters:
    ///     - delay: Delay object to be initialised
    ///     - state: Simulation state in which the delay is initialised.
    /// - Returns: Value of the delay node.
    ///
    public func initialize(delay: BoundDelay, in state: inout SimulationState) throws (EvaluationError) -> Variant {
        let outputValue: Variant
        if let intialValue = delay.initialValue {
            outputValue = intialValue
        }
        else {
            outputValue = state[delay.inputValueIndex]
        }
        guard case let .atom(atom) = outputValue else {
            throw .valueError(.atomExpected)
        }

        var queue: VariantArray = VariantArray(type: delay.valueType)
        if delay.steps > 0 {
            do {
                try queue.append(atom)
            }
            catch {
                throw .valueError(error)
            }
        }
        state[delay.queueIndex] = .array(queue)
        
        return outputValue
    }
    
    /// Initialise a simulated delay.
    ///
    /// The function prepares internal variable holding the smooth state and returns an
    /// initial value of the smooth node.
    ///
    /// - Parameters:
    ///     - smooth: Smooth object to be initialised
    ///     - state: Simulation state in which the smooth is initialised.
    /// - Returns: Value of the smooth node.
    ///
    public func initialize(smooth: BoundSmooth, in state: inout SimulationState) -> Variant {
        let initialValue: Variant = state[smooth.inputValueIndex]
        state[smooth.smoothValueIndex] = initialValue
        
        return initialValue
    }

    // MARK: - Computation
    
    /// Update the simulation state.
    ///
    /// This is the main method that performs the concrete computation using a concrete solver.
    ///
    public func step(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        let result: SimulationState
        
        switch solver {
        case .euler: result = try integrateWithEuler(state)
        case .rk4: result = try integrateWithRK4(state)
        }
        
        return result
    }

    /// Creates a copy of a state and advances the time.
    ///
    /// The returned state has time-dependent built-in variables updated.
    ///
    /// This is a designated method to get a new state before performing computation of the next
    /// step.
    ///
    public func advance(_ state: SimulationState, time: Double? = nil, timeDelta: Double? = nil) -> SimulationState {
        var newState = state.advanced(time: time, timeDelta: timeDelta)
        setBuiltins(in: &newState)
        return newState
    }
    
    func evaluateFlows(_ state: SimulationState) -> NumericVector {
        var result = NumericVector(zeroCount: plan.flows.count)
        for (i, flow) in plan.flows.enumerated() {
            result[i] = state[flow.estimatedValueIndex]
        }
        return result
    }
    
    public func updateAuxiliariesAndFlows(in state: inout SimulationState) throws (SimulationError) {
        for object in plan.simulationObjects {
            guard object.role == .auxiliary || object.role == .flow else { continue }
            try evaluate(object: object, in: &state)
        }
    }
    
    /// Computes and updates a new state of an object.
    ///
    /// If the object computation uses an internal state, it will be updated as
    /// well.
    ///
    /// - Parameters:
    ///     - index: Index of the object to be evaluated.
    ///     - state: simulation state within which the expression is evaluated
    ///
    /// - Throws: ``SimulationError``
    /// - SeeAlso: ``SimulationPlan/stateVariables``
    ///
    public func evaluate(object: SimulationObject, in state: inout SimulationState) throws (SimulationError) {
        let result: Variant
        // FIXME: Delays and smooths should be evaluated before integration, or not?
        do {
            switch object.computation {
                
            case let .formula(expression):
                result = try evaluate(expression: expression, with: state)
                
            case let .graphicalFunction(function):
                result = try evaluate(graphicalFunction: function, with: state)
                
            case let .delay(delay):
                result = try evaluate(delay: delay, in: &state)
                
            case let .smooth(smooth):
                result = try evaluate(smooth: smooth, in: &state)
            }
        }
        catch /* EvaluationError */ {
            throw SimulationError(objectID: object.objectID, error: error)
        }
        
        state[object.variableIndex] = result
    }

    /// Computes and updates a delay value within a simulation state.
    ///
    /// The internal state – the queue holding the delay values is updated.
    ///
    /// - SeeAlso: ``BoundDelay``
    ///
    public func evaluate(delay: BoundDelay, in state: inout SimulationState) throws (EvaluationError) -> Variant {
        guard case let .atom(inputValue) = state[delay.inputValueIndex] else {
            throw .valueError(.atomExpected)
        }
        guard case var .array(queue) = state[delay.queueIndex] else {
            // FIXME: Throw runtime error here
            fatalError("Expected array for delay queue, got atom (compilation is corrupted)")
        }

        let outputValue: VariantAtom
        let nextValue: VariantAtom // Value to be pushed

        if delay.steps == 0 {
            return .atom(inputValue)
        }
        
        if queue.count < delay.steps {
            guard case let .atom(initialValue) = state[delay.initialValueIndex] else {
                throw .valueError(.atomExpected)
            }

            // We do have at least one value in the array (see initialize(delay:...))
            outputValue = initialValue
            nextValue = inputValue
        }
        else {
            outputValue = queue.remove(at:0)
            nextValue = inputValue
        }
        
        do {
            try queue.append(nextValue)
        }
        catch {
            throw .valueError(error)
        }

        state[delay.queueIndex] = .array(queue)

        return .atom(outputValue)
    }

    /// Update an exponential smoothing node.
    ///
    /// The formula: _sₜ = α*xₜ + (1 - α) * sₜ₋₁_
    ///
    /// Where:
    ///
    /// - _x_: input value
    /// - _s_: smooth value
    /// - _α = Δt / w_
    ///
    public func evaluate(smooth: BoundSmooth, in state: inout SimulationState) throws (ValueError) -> Variant {
        
        let inputValue = try state[smooth.inputValueIndex].doubleValue()
        let oldSmooth = state.double(at: smooth.smoothValueIndex)
        
        // TODO: Division by zero - what to do?
        let alpha = state.timeDelta / smooth.windowTime
        let newSmooth = alpha * inputValue + (1 - alpha) * oldSmooth
        
        state[smooth.smoothValueIndex] = Variant(newSmooth)

        return Variant(newSmooth)
    }

    /// Evaluate graphical function
    ///
    /// - Throws: ``SimulationError/functionError(_:_:)`` if the parameter is no convertible to
    /// a numeric type.
    ///
    public func evaluate(graphicalFunction function: BoundGraphicalFunction, with state: SimulationState) throws (EvaluationError) -> Variant {
        let parameter: Double
        do {
            parameter = try state[function.parameterIndex].doubleValue()
        }
        catch {
            throw .valueError(error)
        }
        
        let result = function.function.apply(x: parameter)
        return Variant(result)
    }
}
