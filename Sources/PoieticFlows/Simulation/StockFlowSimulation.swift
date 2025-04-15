//
//  StockFlowSimulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

import PoieticCore

/*
 
 INIT:
    FOR EACH stock
        compute value # requires aux
 
 ITERATE:
 
    STORE initial state # make it current/last state
 
    FOR EACH STAGE:
        FOR EACH aux
            compute value
        FOR EACH flow
            compute flow rate
    ESTIMATE flows
 
 */

/// Stock-Flow simulation specific computation and logic.
///
public class StockFlowSimulation: Simulation {
    /// Simulation plan according which the computation is performed.
    ///
    public let plan: SimulationPlan
    
    public enum SolverType: String, RawRepresentable, CaseIterable {
        case euler
        case rk4
    }
    
    /// Type of a solver to be used for the simulation.
    public var solver: SolverType

    /// Create a new Stock Flow simulation for a specific model.
    ///
    public init(_ plan: SimulationPlan, solver: SolverType = .euler) {
        self.plan = plan
        self.solver = solver
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
    public func initialize(time: Double=0, timeDelta: Double=1.0, override: [ObjectID:Variant]=[:])  throws (SimulationError) -> SimulationState {
        // TODO: [WIP] Move SiulationState.init() code in here, free it from the model
        var state = SimulationState(count: plan.stateVariables.count,
                                    step: 0,
                                    time: time,
                                    timeDelta: timeDelta)

        updateBuiltins(&state)

        for (index, obj) in plan.simulationObjects.enumerated() {
            if let value = override[obj.id] {
                state[obj.variableIndex] = value
            }
            else {
                try initialize(objectAt: index, in: &state)
            }
        }

        return state
    }
    
    /// Set values of built-in variables such as time or time delta.
    ///
    /// - SeeAlso: ``SimulationPlan/builtins``
    ///
    public func updateBuiltins(_ state: inout SimulationState) {
        // NOTE: See also: Compiler.prepareBuiltins() and BuiltinVariable
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
        catch /* EvaluationError */ {
            throw SimulationError(objectID: object.id, error: error)
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
        let initialValue = state[smooth.inputValueIndex]
        state[smooth.smoothValueIndex] = initialValue
        
        return initialValue
    }

    // MARK: - Computation
    
    /// Update the simulation state.
    ///
    /// This is the main method that performs the concrete computation using a concrete solver.
    ///
    public func update(_ state: inout SimulationState) throws (SimulationError) {
        updateBuiltins(&state)

        switch solver {
        case .euler:
            try updateWithEuler(&state)
        case .rk4:
            try updateWithRK4(&state)
        }
        
        for (index, object) in plan.simulationObjects.enumerated() {
            if object.type == .stock {
                continue
            }

            try update(objectAt: index, in: &state)
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
    public func update(objectAt index: Int, in state: inout SimulationState) throws (SimulationError) {
        let object = plan.simulationObjects[index]
        let result: Variant

        do {
            switch object.computation {
                
            case let .formula(expression):
                result = try evaluate(expression: expression, with: state)
                
            case let .graphicalFunction(function):
                result = try evaluate(graphicalFunction: function, with: state)
                
            case let .delay(delay):
                result = try update(delay: delay, in: &state)
                
            case let .smooth(smooth):
                result = try update(smooth: smooth, in: &state)
            }
        }
        catch /* EvaluationError */ {
            throw SimulationError(objectID: object.id, error: error)
        }
        
        state[object.variableIndex] = result
    }

    /// Computes and updates a delay value within a simulation state.
    ///
    /// The internal state – the queue holding the delay values is updated.
    ///
    /// - SeeAlso: ``BoundDelay``
    ///
    public func update(delay: BoundDelay, in state: inout SimulationState) throws (EvaluationError) -> Variant {
        guard case let .atom(inputValue) = state[delay.inputValueIndex] else {
            throw .valueError(.atomExpected)
        }
        guard case var .array(queue) = state[delay.queueIndex] else {
            // FIXME: Use array states
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
    public func update(smooth: BoundSmooth, in state: inout SimulationState) throws (ValueError) -> Variant {
        
        let inputValue = try state[smooth.inputValueIndex].doubleValue()
        let oldSmooth = state.double(at: smooth.smoothValueIndex)
        
        // TODO: Division by zero
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
        
        // TODO: Differentiate function type
        let result = function.function.stepFunction(x: parameter)
        return Variant(result)
    }

    /// Comptes differences of stocks.
    ///
    /// - Returns: A state vector that contains difference values for each
    /// stock.
    ///
    public func stockDifference(state: SimulationState) -> NumericVector {
        var estimate = state
        var deltaVector = NumericVector(zeroCount: plan.stocks.count)

        for (index, stock) in plan.stocks.enumerated() {
            let delta = computeStockDelta(stock, in: &estimate)
            let dtAdjusted = delta * state.timeDelta
            let newValue = estimate.double(at: stock.variableIndex) + dtAdjusted

            estimate[stock.variableIndex] = Variant(newValue)
            deltaVector[index] = dtAdjusted
        }

        return deltaVector
    }
    
    /// Compute a difference of a stock.
    ///
    /// This function computes amount which is expected to be drained from/
    /// filled in a stock and modifies the flows in the input state.
    ///
    /// - Parameters:
    ///     - stock: Stock for which the difference is being computed
    ///     - state: Simulation state vector
    ///
    /// The flows in the state vector will be updated based on constraints.
    /// For example, if the model contains non-negative stocks and a flow
    /// trains a stock with multiple outflows, then other outflows must be
    /// adjusted or set to zero.
    ///
    /// - Note: Current implementation considers are flows to be one-directional
    ///         flows. Flow with negative value, which is in fact an outflow,
    ///         will be ignored.
    ///
    /// - Precondition: The simulation state vector must have all variables
    ///   that are required to compute the stock difference.
    ///
    public func computeStockDelta(_ stock: BoundStock, in state: inout SimulationState) -> Double {
        var totalInflow: Double = 0.0
        var totalOutflow: Double = 0.0
        
        // Compute inflow (regardless whether we allow negative)
        //
        for inflowIndex in stock.inflows {
            // TODO: All flows are uni-flows for now. Ignore negative inflows.
            let inflow = state.double(at: inflowIndex)
            guard inflow.isFinite else { return Double.nan }
            totalInflow += max(inflow, 0)
        }
        
        if stock.allowsNegative {
            for outflow in stock.outflows {
                totalOutflow += state.double(at: outflow)
            }
        }
        else {
            // Compute with a constraint: stock can not be negative
            //
            // We have:
            // - current stock values
            // - expected flow values
            // We need:
            // - get actual flow values based on stock non-negative constraint
            
            // TODO: Add other ways of draining non-negative stocks, not only priority based
            
            // We are looking at a stock, and we know expected inflow and
            // expected outflow. Outflow must be less or equal to the
            // expected inflow plus current state of the stock.
            //
            // Maximum outflow that we can drain from the stock. It is the
            // current value of the stock with aggregate of all inflows.
            //
            var availableOutflow: Double = state.double(at: stock.variableIndex) + totalInflow
            availableOutflow = max(availableOutflow, 0)
            let initialAvailableOutflow: Double = availableOutflow
            for outflowIndex in stock.outflows {
                let outflow = state.double(at: outflowIndex)
                guard outflow.isFinite else { return Double.nan }
                // Assumed outflow value can not be greater than what we
                // have in the stock. We either take it all or whatever is
                // expected to be drained.
                //
                let actualOutflow = min(availableOutflow, max(outflow, 0))
                
                totalOutflow += actualOutflow
                // We drain the stock
                availableOutflow -= actualOutflow
                
                // Adjust the flow value to the value actually drained,
                // so we do not fill another stock with something that we
                // did not drain.
                //
                // FIXME: We are changing the current state, we should be changing some "estimated state"
                state[outflowIndex] = Variant(actualOutflow)
            }
            // Another sanity check. This should always pass, unless we did
            // something wrong above.
            assert(totalOutflow <= initialAvailableOutflow,
                   "Total outflow must not exceed initial available outflow")
        }
        let delta = totalInflow - totalOutflow
        return delta
    }
}
