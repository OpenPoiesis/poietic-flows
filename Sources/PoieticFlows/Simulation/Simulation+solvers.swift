//
//  Simulation+solvers.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

extension StockFlowSimulation {
    /// Adjust the flow rates within a given time unit.
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
    
    @inlinable
    public func flows(_ state: SimulationState) -> NumericVector {
        var flows = NumericVector(zeroCount: plan.flows.count)
        for (i, flow) in plan.flows.enumerated() {
            flows[i] = state[flow.estimatedValueIndex]
        }
        return flows
    }

    @inlinable
    public func stocks(_ state: SimulationState) -> NumericVector {
        var stocks = NumericVector(zeroCount: plan.stocks.count)
        for (i, stock) in plan.stocks.enumerated() {
            stocks[i] = state[stock.variableIndex]
        }
        return stocks
    }
    
    /// Solver that integrates using the Euler method.
    ///
    @inlinable
    public func integrateWithEuler(in state: inout SimulationState) throws (SimulationError) {
        let estimatedFlows = self.flows(state)
        let stocks = self.stocks(state)
       
        let adjustedFlows = adjustFlows(flows: estimatedFlows, stocks: stocks)

        let delta = computeDerivatives(flows: adjustedFlows,
                                       stocks: stocks,
                                       timeDelta: state.timeDelta)
        for (i, stock) in plan.stocks.enumerated() {
            let newStock = state[stock.variableIndex] + delta[i]
            if stock.allowsNegative {
                state[stock.variableIndex] = newStock
            }
            else {
                state[stock.variableIndex] = max(0, newStock)
            }
        }

        for (i, flow) in plan.flows.enumerated() {
            state[flow.adjustedValueIndex] = adjustedFlows[i]
        }
    }
}
