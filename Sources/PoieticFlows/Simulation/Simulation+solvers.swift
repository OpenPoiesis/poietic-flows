//
//  Simulation+solvers.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

extension StockFlowSimulation {
    /// Solver that integrates using the Euler method.
    ///
    /// - SeeAlso: [Euler method](https://en.wikipedia.org/wiki/Euler_method)
    ///
    @discardableResult
    public func updateWithEuler(_ state: inout SimulationState) throws (SimulationError) -> NumericVector {
        let delta = stockDifference(state: state)
        state.numericAdd(delta, atIndices: plan.stockIndices)
        return delta
    }

    /// Solver that integrates using the Runge Kutta 4 method.
    ///
    /// - SeeAlso: [Runge Kutta methods](https://en.wikipedia.org/wiki/Runge–Kutta_methods)
    /// - Important: Does not work well with non-negative stocks.
    ///
    @discardableResult
    public func updateWithRK4(_ state: inout SimulationState) throws (SimulationError) -> NumericVector {
        /*
         RK4:
         
         dy/dt = f(t,y)
         
         k1 = f(tn, yn)
         k2 = f(tn + h/2, yn + h*k1/2)
         k3 = f(tn + h/2, yn + h*k2/2)
         k4 = f(tn + h, yn + h*k3)
         
         yn+1 = yn + 1/6(k1 + 2k2 + 2k3 + k4)*h
         tn+1 = tn + h
         */
        // TODO: Does not work well with non-negative stocks.
        // Is this the issue?
        // https://arxiv.org/abs/2005.06268
        // Paper: "Positivity-Preserving Adaptive Runge-Kutta Methods"

        let stocks = plan.stockIndices
        
        // FIXME: This needs attention, after some recent refactoring the time is unused
        // let time = state.time
        let timeDelta = state.timeDelta
        
        let stage1 = state
        let k1 = stockDifference(state: stage1)
        
        var stage2 = stage1
        stage2.numericAdd(timeDelta * (k1 / 2), atIndices: stocks)
        let k2 = stockDifference(state: stage2)
        
        var stage3 = stage2
        stage3.numericAdd(timeDelta * (k2 / 2), atIndices: stocks)
        let k3 = stockDifference(state: stage3)
        
        var stage4 = stage3
        stage4.numericAdd(k3, atIndices: stocks)
        let k4 = stockDifference(state: stage4)
        
        let resultDelta = (1.0/6.0) * state.timeDelta * (k1 + (2*k2) + (2*k3) + k4)
        
        state.numericAdd(resultDelta, atIndices: stocks)
        
        return resultDelta
    }
    
}
