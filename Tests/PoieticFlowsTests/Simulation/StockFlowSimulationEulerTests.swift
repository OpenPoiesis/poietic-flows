//
//  StockFlowSimulationEulerTests.swift
//  PoieticFlows
//
//  Tests for the Euler integrator.
//
//  Fixtures are defined in SimulationFixtures.swift.
//
//  DISCLAIMER: These tests were written collaboratively with agent assistance.

import Testing
import Foundation
@testable import PoieticCore
@testable import PoieticFlows


@Suite struct StockFlowSimulationEulerTests {

    @Test func constantInflowAdvancesStockByFlowTimesDt() throws {
        // Model: ( inflow ) ---> | stock |
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation(solver: .euler)

        let one = try run(simulation, steps: 1, dt: 1.0)
        let two = try run(simulation, steps: 2, dt: 1.0)

        #expect(one.stocks[0].approxEqual(to: 10))
        #expect(two.stocks[0].approxEqual(to: 20))
    }

    @Test func constantInflowRespectsTimeDelta() throws {
        // Model: ( inflow ) ---> | stock |
        // Regression test: the Euler integrator must scale the rate by dt.
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation(solver: .euler)

        let half = try run(simulation, steps: 2, dt: 0.5)
        let quarter = try run(simulation, steps: 4, dt: 0.25)

        #expect(half.stocks[0].approxEqual(to: 10))
        #expect(quarter.stocks[0].approxEqual(to: 10))
    }

    @Test func outflowIsConstrainedByNonNegativeStock() throws {
        // Model: | stock | ---> ( outflow )
        let model = SimulationFixtures.singleStockOutflow(initialStock: 5, outflow: 10)
        let simulation = model.simulation(solver: .euler)

        let state = try run(simulation, steps: 1, dt: 1.0)

        #expect(state.stocks[0] == 0)
        #expect(state.flows[0].approxEqual(to: 5))     // adjusted to available stock
        #expect(state.numerics[0].approxEqual(to: 10)) // estimate preserved
    }

    @Test func allowsNegativeStockCanGoNegative() throws {
        // Model: | stock | ---> ( outflow )
        let model = SimulationFixtures.singleStockOutflow(initialStock: 5,
                                                          outflow: 10,
                                                          allowsNegative: true)
        let simulation = model.simulation(solver: .euler)

        let state = try run(simulation, steps: 1, dt: 1.0)

        #expect(state.stocks[0].approxEqual(to: -5))
        #expect(state.flows[0].approxEqual(to: 10))    // no constraint applied
    }

    @Test func exponentialGrowthUsesExplicitEuler() throws {
        // Model: ( inflow: stock value ) ---> | stock |
        let model = SimulationFixtures.exponential(initialStock: 1)
        let simulation = model.simulation(solver: .euler)

        let state = try run(simulation, steps: 1, dt: 1.0)

        // y1 = y0 + dt * y0
        #expect(state.stocks[0].approxEqual(to: 2))
    }

    @Test func stockCycle() throws {
        // Two stocks exchanging flows: a -> b and b -> a. When b is empty, its
        // outflow must be constrained to zero, so the first step moves a net
        // amount of 2 from a to b; afterwards the net transfer is 1.
        let aID = ObjectID(intValue: 1)
        let bID = ObjectID(intValue: 2)
        let abID = ObjectID(intValue: 3)
        let baID = ObjectID(intValue: 4)

        let plan = SimulationFixtures.makePlan(
            stocks: [
                SimulationFixtures.Stock(aID, name: "a", initialValue: 10),
                SimulationFixtures.Stock(bID, name: "b", initialValue: 0),
            ],
            flows: [
                SimulationFixtures.Flow(abID, name: "a_to_b", value: 2,
                                        fills: bID, drains: aID),
                SimulationFixtures.Flow(baID, name: "b_to_a", value: 1,
                                        fills: aID, drains: bID),
            ]
        )
        let simulation = StockFlowSimulation(plan)

        let state0 = try simulation.initialize(time: 0, timeDelta: 1)
        let state1 = try simulation.step(state0)
        #expect(state1.stocks[0].approxEqual(to: 8))   // a: 10 - 2 + 0
        #expect(state1.stocks[1].approxEqual(to: 2))   // b: 0 + 2 - 0

        let state2 = try simulation.step(state1)
        #expect(state2.stocks[0].approxEqual(to: 7))   // a: 8 - 2 + 1
        #expect(state2.stocks[1].approxEqual(to: 3))   // b: 2 + 2 - 1
    }
}
