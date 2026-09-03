//
//  Simulation+evaluate.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 02/09/2026.
//

import PoieticCore

extension StockFlowSimulation {
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
        guard !state.isConstant(object.variable) else { return }
        
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
        catch {
            throw .evaluationError(object.objectID, error)
        }
        // TODO: [REFACTORING] Handle known numerics
        do {
            try state.setValue(result, for: object.variable)
        }
        catch {
            throw .evaluationError(object.objectID, .valueError(error))
        }
    }

    /// Computes and updates a delay value within a simulation state.
    ///
    /// The internal state – the queue holding the delay values is updated.
    ///
    /// - SeeAlso: ``BoundDelay``
    ///
    public func evaluate(delay: BoundDelay, in state: inout SimulationState) throws (EvaluationError) -> Variant {
        guard case let .atom(inputValue) = state.variants[delay.inputValueIndex] else {
            throw .valueError(.atomExpected)
        }
        guard case var .array(queue) = state.variants[delay.queueIndex] else {
            // Unreachable
            fatalError("Expected array for delay queue, got atom (planning is corrupted)")
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
        
        queue.append(nextValue)

        state.variants[delay.queueIndex] = .array(queue)

        // TODO: Can we store it directly here?
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
    public func evaluate(smooth: BoundSmooth, in state: inout SimulationState) throws (EvaluationError) -> Variant {
        
        let inputValue = state.numerics[smooth.inputValueIndex]
        let oldSmooth = state.numerics[smooth.smoothValueIndex]
        
        // TODO: Division by zero - what to do?
        let alpha = state.timeDelta / smooth.windowTime
        let newValue = alpha * inputValue + (1 - alpha) * oldSmooth
        
        state.numerics[smooth.smoothValueIndex] = newValue

        // TODO: Can we store it directly here instead of variant wrap-unwrap?
        return Variant(newValue)
    }

    /// Evaluate graphical function
    ///
    /// - Throws: `EvaluationError/valueError` if the parameter is no convertible to
    ///   a numeric type.
    ///
    public func evaluate(graphicalFunction function: BoundGraphicalFunction, with state: SimulationState) throws (EvaluationError) -> Variant {
        let parameter = state.numerics[function.parameterIndex]
        let result = function.function.apply(x: parameter)
        // TODO: Can we store it directly here instead of variant wrap-unwrap?
        return Variant(result)
    }

}
