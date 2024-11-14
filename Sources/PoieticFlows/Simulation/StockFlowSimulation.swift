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
    /// Compiled model for which we are computing.
    ///
    public let model: CompiledModel
    
    var stocks: [CompiledStock] { model.stocks }
    
    public enum SolverType: String, RawRepresentable, CaseIterable {
        case euler
        case rk4
    }
    
    /// Type of a solver to be used for the simulation.
    public var solver: SolverType

    /// Create a new Stock Flow simulation for a specific model.
    ///
    public init(_ model: CompiledModel, solver: SolverType = .euler) {
        self.model = model
        self.solver = solver
    }
    
    // MARK: - Initialization
    
    /// Initialise a simulation state.
    ///
    /// This function computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter.
    /// 
    public func initialize(_ state: inout SimulationState) throws {
        // TODO: Return new state, do not update a state.
        for (index, _) in model.simulationObjects.enumerated() {
            try initialize(objectAt: index, in: &state)
        }
    }
    
    /// Initialise an object in a given state.
    ///
    /// - Parameters:
    ///     - index: Index of the object to be evaluated.
    ///     - state: simulation state within which the expression is evaluated
    ///
    public func initialize(objectAt index: Int, in state: inout SimulationState) throws {
        let object = model.simulationObjects[index]
        let result: Variant
       
        switch object.computation {
        case let .formula(expression):
            result = try evaluate(expression: expression,
                                  with: state)
            
        case let .graphicalFunction(function, index):
            let value = state[index]
            result = try function.apply([value])
        case let .delay(delay):
            result = try initialize(delay: delay, in: &state)
        case let .smooth(smooth):
            result = try initialize(smooth: smooth, in: &state)
        }

        state[object.variableIndex] = result
    }

    /// Initialise a delay object.
    ///
    /// - Parameters:
    ///     - delay: Delay to be initialised
    ///     - state: State in which the delay is initialised.
    /// - Returns: Value of the delay.
    ///
    public func initialize(delay: CompiledDelay, in state: inout SimulationState) throws -> Variant {
        let outputValue: Variant
        if let intialValue = delay.initialValue {
            outputValue = intialValue
        }
        else {
            outputValue = state[delay.inputValueIndex]
        }
        state[delay.queueIndex] = .array(VariantArray(type: delay.valueType))
        
        return outputValue
    }
    public func initialize(smooth: CompiledSmooth, in state: inout SimulationState) throws -> Variant {
        let initialValue = state[smooth.inputValueIndex]
        state[smooth.smoothValueIndex] = initialValue
        
        return initialValue
    }

    // MARK: - Computation
    /// Update the simulation state.
    ///
    /// This is the main method that performs the concrete computation using a concrete solver.
    ///
    public func update(_ state: inout SimulationState) throws {
        switch solver {
        case .euler:
            try updateWithEuler(&state)
        case .rk4:
            try updateWithRK4(&state)
        }
        
        for (index, object) in model.simulationObjects.enumerated() {
            // Skip the stocks
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
    /// - SeeAlso: ``CompiledModel/stateVariables``
    ///
    public func update(objectAt index: Int, in state: inout SimulationState) throws {
        let object = model.simulationObjects[index]
        let result: Variant
        
        switch object.computation {

        case let .formula(expression):
            result = try evaluate(expression: expression, with: state)

        case let .graphicalFunction(function, index):
            let value = state[index]
            result = try function.apply([value])

        case let .delay(delay):
            result = try update(delay: delay, in: &state)
        case let .smooth(smooth):
            result = try update(smooth: smooth, in: &state)
        }
        state[object.variableIndex] = result
    }

    /// Computes and updates a delay value within a simulation state.
    ///
    /// Delay-related internal state will be updated as well.
    ///
    /// - SeeAlso: ``CompiledDelay``
    ///
    public func update(delay: CompiledDelay, in state: inout SimulationState) throws -> Variant {
        guard case let .atom(inputValue) = state[delay.inputValueIndex] else {
            // TODO: Runtime error
            fatalError("Expected atom for delay input value, got array (runtime error)")
        }
        guard case var .array(queue) = state[delay.queueIndex] else {
            fatalError("Expected array for delay queue, got atom (compilation is corrupted)")
        }

        let outputValue: VariantAtom
        let nextValue: VariantAtom // Value to be pushed
        
        // TODO: Use `step` as future function parameter instead of this workaround for queue lenght
        if queue.count + 1 < delay.steps {
            guard case let .atom(initialValue) = state[delay.initialValueIndex] else {
                // TODO: Runtime error
                fatalError("Expected atom for delay initial value, got array (runtime error)")
            }

            // We do have at least one value in the array (see initialize(delay:...))
            outputValue = initialValue
            nextValue = initialValue
        }
        else {
            outputValue = queue.remove(at:0)
            nextValue = inputValue
        }
        try queue.append(nextValue)
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
    public func update(smooth: CompiledSmooth, in state: inout SimulationState) throws -> Variant {
        
        let inputValue = try state[smooth.inputValueIndex].doubleValue()
        let oldSmooth = state.double(at: smooth.smoothValueIndex)
        
        let alpha = state.timeDelta / smooth.windowTime
        let newSmooth = alpha * inputValue + (1 - alpha) * oldSmooth
        
        state[smooth.smoothValueIndex] = Variant(newSmooth)

        return Variant(newSmooth)
    }

    /// Comptes differences of stocks.
    ///
    /// - Returns: A state vector that contains difference values for each
    /// stock.
    ///
    public func stockDifference(state: SimulationState, time: Double) throws -> NumericVector {
        var estimate = state
        var deltaVector = NumericVector(zeroCount: stocks.count)

        for (index, stock) in stocks.enumerated() {
            let delta = try computeStockDelta(stock, in: &estimate)
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
    public func computeStockDelta(_ stock: CompiledStock, in state: inout SimulationState) throws -> Double {
        var totalInflow: Double = 0.0
        var totalOutflow: Double = 0.0
        
        // Compute inflow (regardless whether we allow negative)
        //
        for inflow in stock.inflows {
            // TODO: All flows are uni-flows for now. Ignore negative inflows.
            totalInflow += max(state.double(at: inflow), 0)
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
            let initialAvailableOutflow: Double = availableOutflow

            for outflow in stock.outflows {
                // Assumed outflow value can not be greater than what we
                // have in the stock. We either take it all or whatever is
                // expected to be drained.
                //
                let actualOutflow = min(availableOutflow,
                                        max(state.double(at: outflow), 0))
                
                totalOutflow += actualOutflow
                // We drain the stock
                availableOutflow -= actualOutflow
                
                // Adjust the flow value to the value actually drained,
                // so we do not fill another stock with something that we
                // did not drain.
                //
                // FIXME: We are changing the current state, we should be changing some "estimated state"
                state[outflow] = Variant(actualOutflow)

                // Sanity check. This should always pass, unless we did
                // something wrong above.
                assert(actualOutflow >= 0.0,
                       "Resulting state must be non-negative")
            }
            // Another sanity check. This should always pass, unless we did
            // something wrong above.
            assert(totalOutflow <= initialAvailableOutflow,
                   "Resulting total outflow must not exceed initial available outflow")

        }
        let delta = totalInflow - totalOutflow
        return delta
    }

}
