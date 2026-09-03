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
    ///     - parameters: Dictionary of simulation parameters; parameters are overrides applied
    ///       before evaluation.
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
    /// The ``SimulationState/flows`` and their corresponding estimated flows are the same after
    /// initialisation.
    ///
    /// - Returns: Newly initialised simulation state.
    ///
    public func initialize(time: Double=0,
                           timeDelta: Double=1.0,
                           parameters: [ObjectID:Variant]=[:])
    throws (SimulationError) -> SimulationState
    {
        var state = SimulationState(plan: plan, step: 0, time: time, timeDelta: timeDelta)
        
        // 1. Apply scenario parameters override
        //
        for (objectID, value) in parameters {
            guard let object = plan.simulationObject(objectID)
            else { throw .unknownObject(objectID) }
            
            if object.isAccumulator {
                try initialize(accumulator: object, initialValue: value, in: &state)
            }
            else {
                try write(value, to: object.variable, of: objectID, in: &state)
                state.markAsConstant(object.variable)
            }
        }
        
        // 2. Evaluate the rest
        //
        for object in plan.simulationObjects where parameters[object.objectID] == nil {
            try initialize(object: object, in: &state)
        }
        
        // 3. Copy flows – before adjustment the estimates are the same
        for (index, flow) in plan.flows.enumerated() {
            state.numerics[flow.estimatedNumericIndex] = state.flows[index]
        }
        
        return state
    }
    
    
    /// Initialise an object by evaluating its content.
    ///
    /// - SeeAlso: ``SimulationObject/computation``
    ///
    public func initialize(object: SimulationObject, in state: inout SimulationState)
    throws (SimulationError)
    {
        let result: Variant
        switch object.computation {
        case let .formula(expression):
            do {
                result = try Evaluator.evaluate(expression: expression, lookup: state)
            }
            catch {
                throw .evaluation(object.objectID, error)
            }
        case let .graphicalFunction(function):
            do {
                result = try evaluate(graphicalFunction: function, with: state)
            }
            catch {
                throw .evaluation(object.objectID, error)
            }
        case let .delay(delay):
            result = try initialize(delay: delay, initialValue: nil, objectID: object.objectID, in: &state)
        case let .smooth(smooth):
            result = try initialize(smooth: smooth, initialValue: nil, objectID: object.objectID, in: &state)
        }


        try write(result, to: object.variable, of: object.objectID, in: &state)
    }
    
    /// Initialise an accumulator with an explicit initial value.
    ///
    /// This function is called by ``initialize(time:timeDelta:parameters:)`` when a parameter of
    /// an accumulator is set.
    ///
    /// - SeeAlso: ``SimulationObject/isAccumulator``
    ///
    func initialize(accumulator: SimulationObject,
                    initialValue: Variant,
                    in state: inout SimulationState)
    throws (SimulationError)
    {
        try write(initialValue, to: accumulator.variable, of: accumulator.objectID, in: &state)
        
        switch accumulator.computation {
        case let .delay(delay):
            try initialize(delay: delay, initialValue: initialValue, objectID: accumulator.objectID, in: &state)
        case let .smooth(smooth):
            try initialize(smooth: smooth, initialValue: initialValue, objectID: accumulator.objectID, in: &state)
        case .formula, .graphicalFunction: break
        }
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
//    @discardableResult
    public func initialize(delay: BoundDelay,
                           initialValue: Variant?,
                           objectID: ObjectID,
                           in state: inout SimulationState)
    throws (SimulationError) -> Variant
    {
        let result: Variant

        if let initialValue                    { result = initialValue }
        else if let value = delay.initialValue { result = value }
        else                                   { result = state[delay.inputValueRef] }

        guard case let .atom(atom) = result else { throw .atomExpected(objectID) }

        var queue: VariantArray

        // Variant array type mismatches are handled in evaluate(delay:...)
        if delay.steps > 0 { queue = VariantArray(ofOne: atom) }
        else               { queue = VariantArray(type: delay.valueType) }

        state.variants[delay.queueIndex] = .array(queue)
        try write(result, to: delay.initialValueRef, of: objectID, in: &state)

        return result
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
//    @discardableResult
    public func initialize(smooth: BoundSmooth,
                           initialValue: Variant?,
                           objectID: ObjectID,
                           in state: inout SimulationState)
    throws (SimulationError) -> Variant
    {
        let result: Variant
        if let initialValue {
            result = initialValue
            try write(initialValue, to: .numeric(smooth.smoothValueIndex), of: objectID, in: &state)
        }
        else {
            let value = state.numerics[smooth.inputValueIndex]
            state.numerics[smooth.smoothValueIndex] = value
            result = Variant(value)
        }
        
        return result
    }
}
