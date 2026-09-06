//
//  StockFlowSimulationRK4Tests.swift
//  PoieticFlows
//
//  Tests for the Runge-Kutta 4 integrator.
//
//  Fixtures are defined in SimulationFixtures.swift.
//
//  NOTE: These tests were written with agent assistance, reviewed and validated by a human.

import Testing
import Foundation
@testable import PoieticCore
@testable import PoieticFlows


@Suite struct StockFlowSimulationRK4Tests {

    @Test func constantInflowMovesStockByExactAmount() throws {
        // Model: ( inflow ) ---> | stock |
        // Regression test for the original RK4 bug: a constant flow must move
        // the stock by exactly flow * dt (the old implementation gave 6.67).
        let model = SimulationFixtures.singleStockInflow(initialStock: 1, inflow: 10)
        let simulation = model.simulation(solver: .rk4)

        let state = try run(simulation, steps: 1, dt: 1.0)

        #expect(state.stocks[0].approxEqual(to: 11))
    }

    @Test func constantInflowIsIndependentOfTimeDelta() throws {
        // Model: ( inflow ) ---> | stock |
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation(solver: .rk4)

        let one = try run(simulation, steps: 1, dt: 1.0)
        let half = try run(simulation, steps: 2, dt: 0.5)
        let quarter = try run(simulation, steps: 4, dt: 0.25)

        #expect(one.stocks[0].approxEqual(to: 10))
        #expect(half.stocks[0].approxEqual(to: 10))
        #expect(quarter.stocks[0].approxEqual(to: 10))
    }

    @Test func exponentialGrowthMatchesAnalyticSolution() throws {
        // y' = y, y0 = 1. The RK4 error should shrink ~16x when dt halves
        // (fourth order).
        let model = SimulationFixtures.exponential(initialStock: 1)
        let simulation = model.simulation(solver: .rk4)

        let oneStep = try run(simulation, steps: 1, dt: 1.0)
        let twoHalfSteps = try run(simulation, steps: 2, dt: 0.5)

        let e = exp(1.0)
        #expect(oneStep.stocks[0].approxEqual(to: e, tolerance: 0.02))
        #expect(twoHalfSteps.stocks[0].approxEqual(to: e, tolerance: 0.005))
    }

    @Test func nonNegativeStockDoesNotGoNegative() throws {
        // Model: | stock | ---> ( outflow )
        let model = SimulationFixtures.singleStockOutflow(initialStock: 1, outflow: 10)
        let simulation = model.simulation(solver: .rk4)

        let state = try run(simulation, steps: 1, dt: 1.0)

        #expect(state.stocks[0] >= 0)
    }

    @Test func storesAdjustedFlowAndEstimatedValue() throws {
        // Model: | stock | ---> ( outflow )
        // The flows vector at rest holds the adjusted flow; the estimate is
        // preserved in numerics. With RK4 and a constrained outflow the stock
        // may not drain fully in one step, so only assert the convention, not
        // the exact drained amount.
        let model = SimulationFixtures.singleStockOutflow(initialStock: 5, outflow: 10)
        let simulation = model.simulation(solver: .rk4)

        let state = try run(simulation, steps: 1, dt: 1.0)

        #expect(state.stocks[0] >= 0)
        #expect(state.flows[0] > 0)
        #expect(state.flows[0] < 10)                    // constrained below estimate
        #expect(state.numerics[0].approxEqual(to: 10))  // estimate preserved
    }
}
