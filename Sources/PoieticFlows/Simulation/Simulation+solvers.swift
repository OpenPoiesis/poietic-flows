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
    ///     - estimated: Estimated flow rates – rates as computed by the user-provided computation
    ///              the model.
    ///     - stocks: Vector of stock values.
    ///
    /// The items of `estimated` correspond to the items in the simulation plan's `flows` and the items
    /// in `stocks` correspond to the items in the simulation plan's `stocks`.
    ///
    @inlinable
    func adjustFlows(estimated: NumericVector, stocks: NumericVector) -> NumericVector {
        var adjusted = estimated
        
        for (s, stock) in plan.stocks.enumerated() {
            guard !stock.allowsNegative else { continue }
            
            // The outflow sum is taken from the estimates: this stock is the
            // source of all its outflows, so no other stock scales them.
            let outflow: Double = estimated[stock.outflows].sum()
            // The inflow sum is taken from the adjusted values: an inflow is an
            // outflow of another stock and may have been scaled already.
            // NOTE: This relies on the source stock being processed before the
            // filling stock in `plan.stocks` order.
            let inflow: Double = adjusted[stock.inflows].sum()
            
            let current = max(0, stocks[s])
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

    
    /// Net rate of change for each stock, given applied (adjusted) flows.
    ///
    /// - Note: No non-negative stock constraints are applied here.
    ///
    func computeNetRates(flows: NumericVector) -> NumericVector {
        var result = NumericVector(zeroCount: plan.stocks.count)
        
        for (index, stock) in plan.stocks.enumerated() {
            result[index] = flows[stock.inflows].sum() - flows[stock.outflows].sum()
        }
        
        return result
    }
    
    
    /// Update the stocks with given derivative (delta).
    ///
    /// The function also performs a fail-safe clamping of non-negative stocks, setting them to 0 if
    /// they underflow.
    @inlinable
    func clampNonNegativeStocks(in state: inout SimulationState) {
        for (i, value) in state.stocks.enumerated() {
            if plan.stocks[i].allowsNegative {
                state.stocks[i] = value
            }
            else {
                state.stocks[i] = max(0, value)
            }
        }
    }

    /// Copy a state and advance the time.
    ///
    /// This is a designated method to get a new state before performing computation of the next
    /// step.
    ///
    public func advance(_ state: SimulationState,
                        stockDelta: NumericVector,
                        step: Int,
                        time: Double,
                        timeDelta: Double) -> SimulationState
    {
        precondition(stockDelta.count == state.stocks.count)

        var result = state.adding(stocks: stockDelta, step: step, time: time, timeDelta: timeDelta)
        clampNonNegativeStocks(in: &result)

        return result
    }

    /// Move compute flow estimates into their numeric variable slots and replace the flows vector
    /// with applied (adjusted) flows.
    ///
    /// Called once, at the end of each integrator, after final call to ``updateAuxiliariesAndFlows(in:)``.
    ///
    func storeAdjustedFlows(_ adjustedFlows: NumericVector, in state: inout SimulationState) {
        for (index, flow) in plan.flows.enumerated() {
            let estimated = state.flows[index]
            state.flows[index] = adjustedFlows[index]
            state.numerics[flow.estimatedNumericIndex] = estimated
        }
    }
    
    /// Computes stock rates
    ///
    /// 1. Evaluates auxiliaries and flow estimates with the previous stock values.
    /// 2. Computes adjusted flow rates.
    /// 3. Computes net stock rates.
    ///
    /// - Returns net stock rates and adjusted flows.
    ///
    func rates(_ state: SimulationState)
    throws (SimulationError) -> (rates: NumericVector, adjustedFlows: NumericVector)
    {
        var evaluated = state
        try updateAuxiliariesAndFlows(in: &evaluated)
        
        // At this point, the `evaluated` still holds the computed - estimated flows in the flows vector.
        // We shift them at the end of integration.
        let adjustedFlows = self.adjustFlows(estimated: evaluated.flows, stocks: evaluated.stocks)
        let rates = self.computeNetRates(flows: adjustedFlows)
        
        return(rates: rates, adjustedFlows: adjustedFlows)
    }
    
    func integrateWithRK4(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        let dt = state.timeDelta
        let time = state.time
        let halfDt = dt / 2.0
        
        // Stage 1
        let (k1, adjustedFlows1) = try rates(state)
        
        // Stage 2
        let stage2 = advance(state, stockDelta: k1 * halfDt, step: state.step, time: time + halfDt, timeDelta: dt)
        let (k2, adjustedFlows2) = try rates(stage2)
        
        // Stage 3
        let stage3 = advance(state, stockDelta: k2 * halfDt, step: state.step, time: time + halfDt, timeDelta: dt)
        let (k3, adjustedFlows3) = try rates(stage3)

        // Stage 4
        let stage4 = advance(state, stockDelta: k3 * dt, step: state.step, time: time + dt, timeDelta: dt)
        let (k4, adjustedFlows4) = try rates(stage4)
        
        let weightedRate = (k1 + 2*k2 + 2*k3 + k4) / 6
        let stockDelta = weightedRate * dt
        
        var result = advance(state, stockDelta: stockDelta, step: state.step+1, time: time + dt, timeDelta: dt)

        try updateAuxiliariesAndFlows(in: &result)
        let finalAdjustedFlows = (adjustedFlows1
                                  + 2 * adjustedFlows2
                                  + 2 * adjustedFlows3
                                  + adjustedFlows4) / 6
        
        storeAdjustedFlows(finalAdjustedFlows, in: &result)
        
        return result
    }
    
    func integrateWithEuler(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        let (stockRates, adjustedFlows) = try rates(state)
        let stockDelta = stockRates * state.timeDelta

        var result = advance(state,
                             stockDelta: stockDelta,
                             step: state.step+1,
                             time: state.time + state.timeDelta,
                             timeDelta: state.timeDelta)

        try updateAuxiliariesAndFlows(in: &result)
        storeAdjustedFlows(adjustedFlows, in: &result)
        
        return result
    }
}
