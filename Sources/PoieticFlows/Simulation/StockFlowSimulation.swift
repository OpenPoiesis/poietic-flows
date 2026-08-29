//
//  StockFlowSimulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

// FIXME: [IMPORTANT] Test for dt = 0
// TODO: [IMPORTANT] Set object issues when computation fails (for example value conversion, or division by zero). Do not throw.
// TODO: Halt on negative inflow or outflow (optional)

import PoieticCore

// for evaluation
extension SimulationState: VariableValueLookup {
    public typealias Variable = BoundVariable
    public func value(for variable: Variable) -> Variant {
        return self[variable.index]
    }
}

public struct SimulationError: Error {
    let objectID: ObjectID
    let error: any Error
}

/// Stock-Flow simulation specific computation and logic.
///
public class StockFlowSimulation {
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
    
    /// Indices of variables that are to remain constant – they are set during initialisation from
    /// a simulation parameter and then are not re-evaluated during simulation run.
    ///
    /// - SeeAlso: ``initialize(object:withParameter:in:)``
    ///
    private var constantIndices: Set<SimulationState.Index>

    /// Create a new Stock Flow simulation for a specific model.
    ///
    public init(_ plan: SimulationPlan, solver: SolverType = .euler, flowScaling: FlowScaling = .outflowFirst) {
        self.plan = plan
        self.solver = solver
        self.flowScaling = flowScaling
        self.constantIndices = Set()
    }
   
    // MARK: - Initialization
    /// Create and initialise a simulation state.
    ///
    /// - Parameters:
    ///     - time: Initial time.
    ///     - timeDelta: Time delta between simulation steps.
    ///     - parameters: Dictionary of simulation parameters. See note below.
    ///
    /// This function creates and computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter. The order is provided
    /// by the ``SimulationPlan/simulationObjects``.
    ///
    /// ## Discussion
    ///
    /// If a parameter for an object **is not provided**: object value is evaluated as specified
    /// in its computational representation.
    ///
    /// If a parameter for an object **is provided**: the object is initialised to given parameter
    /// value. For accumulator objects (stock, delay, smooth) the parameter is used only to set
    /// the initial value, later during the computation the value is disregarded. For objects that
    /// are not accumulators (flow rates, auxiliaries, graphical function, ...) the parameter value
    /// is preserved as their constant through the whole simulation run.
    ///
    /// - Returns: Newly initialised simulation state.
    ///
    public func initialize(time: Double=0,
                           timeDelta: Double=1.0,
                           parameters: [ObjectID:Variant]=[:])
    throws (SimulationError) -> SimulationState
    {
        self.constantIndices = Set()
        
        var state = SimulationState(count: plan.stateVariables.count,
                                    step: 0,
                                    time: time,
                                    timeDelta: timeDelta)
        
        setBuiltins(in: &state)
        
        for object in plan.simulationObjects {
            try initialize(object: object, withParameter: parameters[object.objectID], in: &state)
        }
        
        return state
    }
    
    /// Initialise a simulation object value in the simulation state.
    ///
    /// - Parameters:
    ///     - object: Simulation object to be initialised in the state.
    ///     - parameter: Parameter to be used for initialisation. See note below.
    ///     - state: Simulation state to be initialised
    ///
    /// If the parameter **is not provided** (is `nil`): object value is evaluated as specified
    /// in its computational representation.
    ///
    /// If the parameter **is provided**: the object is initialised to given parameter value.
    /// For accumulator objects (stock, delay, smooth) the parameter is used only for
    /// initialisation, later during computation it is disregarded. For objects that are not
    /// accumulators (flow rates, auxiliaries, graphical function, ...) the parameter value is
    /// preserved as their constant through the simulation.
    ///
    public func initialize(object: SimulationObject,
                           withParameter parameter: Variant?,
                           in state: inout SimulationState)
    throws (SimulationError)
    {
        if let parameter {
            if object.isAccumulator {
                try initialize(accumulator: object, initialValue: parameter, in: &state)
            }
            else {
                state[object.variableIndex] = parameter
                constantIndices.insert(object.variableIndex)
            }
        }
        else {
            try initialize(object: object, in: &state)
        }
    }
    
    /// Initialise an object without a parameter.
    public func initialize(object: SimulationObject, in state: inout SimulationState)
    throws (SimulationError)
    {
        let result: Variant
        do {
            switch object.computation {
            case let .formula(expression):
                result = try Evaluator.evaluate(expression: expression, lookup: state)
            case let .graphicalFunction(function):
                result = try evaluate(graphicalFunction: function, with: state)
            case let .delay(delay):
                result = try initialize(delay: delay, initialValue: nil, in: &state)
            case let .smooth(smooth):
                result = initialize(smooth: smooth, initialValue: nil, in: &state)
            }
        }
        catch {
            throw SimulationError(objectID: object.objectID, error: error)
        }
        state[object.variableIndex] = result
    }
    
    /// Initialise an accumulator with a value.
    func initialize(accumulator: SimulationObject,
                    initialValue: Variant,
                    in state: inout SimulationState)
    throws (SimulationError)
    {
        state[accumulator.variableIndex] = initialValue
        
        do {
            // Treatment for special kinds of accumulators (not explicit Stock)
            switch accumulator.computation {
            case let .delay(delay): try initialize(delay: delay, initialValue: initialValue, in: &state)
            case let .smooth(smooth): initialize(smooth: smooth, initialValue: initialValue, in: &state)
            case .formula, .graphicalFunction: break
            }
        }
        catch {
            throw SimulationError(objectID: accumulator.objectID, error: error)
        }
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
    @discardableResult
    public func initialize(delay: BoundDelay, initialValue: Variant?, in state: inout SimulationState) throws (EvaluationError) -> Variant {
        let outputValue: Variant
        if let initialValue {
            outputValue = initialValue
        }
        else if let value = delay.initialValue {
            outputValue = value
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
        state[delay.initialValueIndex] = outputValue
        
        return outputValue
    }
    
    /// Initialise a simulated smooth.
    ///
    /// The function prepares internal variable holding the smooth state and returns an
    /// initial value of the smooth node.
    ///
    /// - Parameters:
    ///     - smooth: Smooth object to be initialised
    ///     - state: Simulation state in which the smooth is initialised.
    /// - Returns: Value of the smooth node.
    ///
    @discardableResult
    public func initialize(smooth: BoundSmooth, initialValue: Variant?, in state: inout SimulationState) -> Variant {
        let value: Variant = initialValue ?? state[smooth.inputValueIndex]
        state[smooth.smoothValueIndex] = value
        
        return value
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
    /// If the object computation uses an internal state, all associated internal states will be
    /// updated as well.
    ///
    /// If the object is set to be a constant through a simulation parameter, the evaluation is
    /// skipped (the constant value is preserved).
    ///
    /// - Parameters:
    ///     - object: Object to be evaluated.
    ///     - state: simulation state within which the expression is evaluated
    ///
    /// - Throws: ``SimulationError``
    /// - SeeAlso: ``SimulationPlan/stateVariables``, ``initialize(smooth:initialValue:in:)``
    ///
    public func evaluate(object: SimulationObject, in state: inout SimulationState) throws (SimulationError) {
        // Keeping the constants from ``ScenarioParameters``
        guard !constantIndices.contains(object.variableIndex) else { return }
        
        let result: Variant
        // FIXME: Delays and smooths should be evaluated before integration, or not?
        do {
            switch object.computation {
                
            case let .formula(expression):
                result = try Evaluator.evaluate(expression: expression, lookup: state)
                
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
    /// - Throws: `EvaluationError/valueError` if the parameter is no convertible to
    ///   a numeric type.
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
