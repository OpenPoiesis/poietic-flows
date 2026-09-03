//
//  Simulation+solvers.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

extension StockFlowSimulation {
    /// Adjust the flow rates based on flow scaling method.
    ///
    /// - Parameters:
    ///     - flows: Estimated flow rates – rates as computed by the user-provided computation
    ///              the model.
    ///     - stocks: Vector of stock values.
    ///
    /// The items of `flows` correspond to the items in the simulation plan's `flows` and the items
    /// in `stocks` correspond to the items in the simulation plan's `stocks`.
    /// 
    @inlinable
    func adjustFlows(flows estimated: NumericVector, stocks: NumericVector) -> NumericVector {
        var adjusted = estimated
        
        for (s, stock) in plan.stocks.enumerated() {
            guard !stock.allowsNegative else { continue }
            
            let inflow: Double = estimated[stock.inflows].sum()
            let outflow: Double = estimated[stock.outflows].sum()
            
            let current: Double = stocks[s]
            guard outflow > 0 else { continue }
            
            switch flowScaling {
            case .outflowFirst:
                guard outflow > current else { break }
                let scale = min(1, current / outflow)
                for o in stock.outflows {
                    adjusted[o] = estimated[o] * scale
                }
            case .inflowFirst:
                let available = current + inflow
                guard available < outflow else { break }
                let scale = min(1, available / outflow)
                for o in stock.outflows {
                    adjusted[o] = estimated[o] * scale
                }
            }
        }
        return adjusted
    }
    
    /// Compute stock derivatives given adjusted flows.
    ///
    /// - Parameters:
    ///     - flows: Flow rates adjusted for non-negative constraints.
    ///     - stocks: Vector of stock values.
    ///     - timeDelta: Time increment used for computation of the derivative.
    ///
    @inlinable
    func computeDerivatives(flows: NumericVector, stocks: NumericVector, timeDelta: Double) -> NumericVector {
        var delta = NumericVector(zeroCount: plan.stocks.count)
        for (s, stock) in plan.stocks.enumerated() {
            let inflow = flows[stock.inflows].sum()
            let outflow = flows[stock.outflows].sum()
            let netFlow: Double
            if stock.allowsNegative {
                netFlow = (inflow - outflow) * timeDelta
            }
            else {
                // Safeguard clamping (might introduce an error)
                let current: Double = stocks[s]
                netFlow = max(-current, (inflow - outflow) * timeDelta)
            }
            delta[s] = netFlow
        }
        return delta
    }
    
    /// Get a vector with estimated flow rates from the state.
    ///
    /// Estimated flows rates are rates computed using user-provided computations in the model.
    /// Estimated flows need to be adjusted for the constraints before applying.
    @inlinable
    public func flows(_ state: SimulationState) -> NumericVector {
        // FIXME: [REFACTORING] This method is no longer necessary
        return state.flows
    }
    
    /// Get a vector with stock values in the simulation state.
    @inlinable
    public func stocks(_ state: SimulationState) -> NumericVector {
        // FIXME: [REFACTORING] This method is no longer necessary
        return state.stocks
    }
    
    /// Update the stocks with given derivative (delta).
    ///
    /// The function also performs a fail-safe clamping of non-negative stocks, setting them to 0 if
    /// they underflow.
    @inlinable
    func updateStocks(delta: NumericVector, in state: inout SimulationState) {
        precondition(delta.count == state.stocks.count)
        for (i, diff) in delta.enumerated() {
            let value = state.stocks[i] + diff

            if plan.stocks[i].allowsNegative {
                state.stocks[i] = value
            }
            else {
                state.stocks[i] = max(0, value)
            }
        }
    }
    
    /// Solver that integrates using the Euler method.
    ///
    @inlinable
    public func integrateWithEuler(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        var result = advance(state)
        let stocks = self.stocks(state)
        let estimatedFlows = self.flows(state)
        let adjustedFlows = adjustFlows(flows: estimatedFlows, stocks: stocks)
        
        let netFlow = computeDerivatives(flows: adjustedFlows, stocks: stocks, timeDelta: state.timeDelta)
        updateStocks(delta: netFlow, in: &result)
        try updateAuxiliariesAndFlows(in: &result)
        for (i, flow) in plan.flows.enumerated() {
            result.flows[flow.actualValueIndex] = adjustedFlows[i]
        }
        return result
    }
    

    /// Compute a RK method stage.
    ///
    /// - Returns: A tuple _(delta, adjustedRates)_ where `delta` is the computed stock net flow
    /// (vector corresponds to the vector of stocks) and `adjustedFlows` is a vector of size of
    /// flows vector that is used for debug purposes.
    @inlinable
    func computeStage(delta: NumericVector, in state: inout SimulationState) throws (SimulationError) -> (NumericVector, NumericVector) {
        updateStocks(delta: delta, in: &state)
        try updateAuxiliariesAndFlows(in: &state)
        
        let estimatedFlows = self.flows(state)
        let stocks = self.stocks(state)
        let adjustedFlows = adjustFlows(flows: estimatedFlows, stocks: stocks)
        let delta = computeDerivatives(flows: adjustedFlows,
                                       stocks: stocks,
                                       timeDelta: state.timeDelta)
        return (delta, adjustedFlows)
    }
    
    /// Solver that integrates using the Runge-Kutta 4th order method.
    @inlinable
    public func integrateWithRK4(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        let stocks1 = self.stocks(state)
        let estimatedFlows1 = self.flows(state)
        let adjustedFlows1 = self.adjustFlows(flows: estimatedFlows1, stocks: stocks1)
        let k1 = computeDerivatives(flows: adjustedFlows1, stocks: stocks1, timeDelta: state.timeDelta)

        var state2 = advance(state, timeDelta: state.timeDelta/2)
        let (k2, adjustedFlows2) = try computeStage(delta: k1, in: &state2)

        var state3 = advance(state, timeDelta: state.timeDelta/2)
        let (k3, adjustedFlows3) = try computeStage(delta: k2, in: &state3)

        var state4 = advance(state, timeDelta: state.timeDelta)
        let (k4, adjustedFlows4) = try computeStage(delta: k3, in: &state4)

        var result = advance(state)
        let finalNetFlow = (k1 + 2*k2 + 2*k3 + k4) / 6
        updateStocks(delta: finalNetFlow, in: &result)
        try updateAuxiliariesAndFlows(in: &result)

        let finalAdjustedFlows = (adjustedFlows1 + 2*adjustedFlows2 + 2*adjustedFlows3 + adjustedFlows4) / 6
        for (i, flow) in plan.flows.enumerated() {
            result.flows[flow.actualValueIndex] = finalAdjustedFlows[i]
        }
        
        // TODO: Post-clamping of non-negative stocks
        
        return result
    }
}
