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
    func adjustFlows(estimated: NumericVector, stocks: NumericVector) -> NumericVector {
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
        // TODO: [REFACTORING] Consolidate with SimulationState.adding(stocks:...) and StockFlowSimulation.updateStocks(...)
        for (i, value) in state.stocks.enumerated() {
            if plan.stocks[i].allowsNegative {
                state.stocks[i] = value
            }
            else {
                state.stocks[i] = max(0, value)
            }
        }
    }

    func makeStage(from base: SimulationState,
                   stockDelta: NumericVector,
                   time: Double,
                   timeDelta : Double) -> SimulationState {
        var stage = base.adding(stocks: stockDelta,
                                step: base.step,
                                time: time,
                                timeDelta: timeDelta)
        clampNonNegativeStocks(in: &stage)
        return stage
        
    }
    
    func rates(_ state: SimulationState)
    throws (SimulationError) -> (rates: NumericVector, adjustedFlows: NumericVector)
    {
        var evaluated = state
        try updateAuxiliariesAndFlows(in: &evaluated)
        
        // At this point, the state still holds the computed - estimated flows in the flows vector.
        // We shift them at the end of integration.
        let adjustedFlows = self.adjustFlows(estimated: state.flows, stocks: state.stocks)
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
        let stage2 = makeStage(from: state, stockDelta: k1 * halfDt, time: time + halfDt, timeDelta: dt)
        let (k2, adjustedFlows2) = try rates(stage2)
        
        // Stage 3
        let stage3 = makeStage(from: state, stockDelta: k2 * halfDt, time: time + halfDt, timeDelta: dt)
        let (k3, adjustedFlows3) = try rates(stage3)

        // Stage 4
        let stage4 = makeStage(from: state, stockDelta: k3 * dt, time: time + dt, timeDelta: dt)
        let (k4, adjustedFlows4) = try rates(stage4)
        
        let weightedRate = (k1 + 2*k2 + 2*k3 + k4) / 6
        let stockDelta = weightedRate * dt
        
        var result = advance(state)
        updateStocks(delta: stockDelta, in: &result)
        try updateAuxiliariesAndFlows(in: &result)
        let finalAdjustedFlows = (adjustedFlows1
                                  + 2 * adjustedFlows2
                                  + 2 * adjustedFlows3
                                  + adjustedFlows4) / 6
        
        // Shift estimated to numerics and replace them with adjusted
        for (index, flow) in plan.flows.enumerated() {
            let estimated = result.flows[index]
            result.flows[index] = finalAdjustedFlows[index]
            result.numerics[flow.estimatedNumericIndex] = estimated
        }
        
        return result
    }
    
    func integrateWithEuler(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        var result = advance(state)
        let (stockDelta, adjustedFlows) = try rates(state)
        updateStocks(delta: stockDelta, in: &result)

        // TODO: [QUESTION][REFACTORING] We are updating second time. We cloned whole state in rates(...). Is this okay?
        try updateAuxiliariesAndFlows(in: &result)
        
        // Shift estimated to numerics and replace them with adjusted
        for (index, flow) in plan.flows.enumerated() {
            let estimated = result.flows[index]
            result.flows[index] = adjustedFlows[index]
            result.numerics[flow.estimatedNumericIndex] = estimated
        }
        
        return result
    }
    
    /// Update the stocks with given derivative (delta).
    ///
    /// The function also performs a fail-safe clamping of non-negative stocks, setting them to 0 if
    /// they underflow.
    @inlinable
    func updateStocks(delta: NumericVector, in state: inout SimulationState) {
        // TODO: [REFACTORING] Consolidate with SimulationState.adding(stocks:...) and StockFlowSimulation.clampNonNegativeStocks(...)
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
}
