//
//  Simulation+init.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 02/09/2026.
//

import PoieticCore

extension StockFlowSimulation {
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
        for requiredID in parameters.keys {
            guard plan.containsObject(requiredID) else { throw .unknownObject(requiredID) }
        }

        var state = SimulationState(plan: plan,
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
                do {
                    try state.setValue(parameter, for: object.variable)
                }
                catch {
                    throw .evaluationError(object.objectID, .valueError(error))
                }
                state.markAsConstant(object.variable)
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
            throw .evaluationError(object.objectID, error)
        }
        state[object.variable] = result
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
            throw .evaluationError(accumulator.objectID, error)
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
        state.numerics[smooth.smoothValueIndex] = value
        
        return value
    }
}
