//
//  StockFlowSimulationSharedTests.swift
//  PoieticFlows
//
//  Tests for methods shared by the integrators: flow adjustment, net-rate
//  computation, the rate function, clamping, and the estimated/adjusted flow
//  shift.
//
//  Fixtures are defined in SimulationFixtures.swift.
//
//  NOTE: These tests were written with agent assistance, reviewed and validated by a human.


import Testing
@testable import PoieticCore
@testable import PoieticFlows

// MARK: - Shared method tests
@Suite struct StockFlowSimulationSharedTests {

    @Test func adjustFlowsOutflowFirstUsesCurrentStock() throws {
        // Model: ( inflow ) ---> | stock | ---> ( outflow )
        let model = SimulationFixtures.stockWithInflowAndOutflow(
            initialStock: 5,
            inflow: 10,
            outflow: 20
        )
        let simulation = model.simulation(flowScaling: .outflowFirst)

        let adjusted = simulation.adjustFlows(estimated: NumericVector([10, 20]),
                                              stocks: NumericVector([5]))

        #expect(adjusted[0].approxEqual(to: 10))   // inflow untouched
        #expect(adjusted[1].approxEqual(to: 5))    // outflow scaled to current stock
    }

    @Test func adjustFlowsInflowFirstUsesAvailableStock() throws {
        // Model: ( inflow ) ---> | stock | ---> ( outflow )
        let model = SimulationFixtures.stockWithInflowAndOutflow(
            initialStock: 5,
            inflow: 10,
            outflow: 20
        )
        let simulation = model.simulation(flowScaling: .inflowFirst)

        let adjusted = simulation.adjustFlows(estimated: NumericVector([10, 20]),
                                              stocks: NumericVector([5]))

        #expect(adjusted[0].approxEqual(to: 10))   // inflow untouched
        #expect(adjusted[1].approxEqual(to: 15))   // current + inflow available
    }

    @Test func adjustFlowsLeavesFlowsUntouchedWhenStockIsSufficient() throws {
        // Model: ( inflow ) ---> | stock | ---> ( outflow )
        let model = SimulationFixtures.stockWithInflowAndOutflow(
            initialStock: 50,
            inflow: 10,
            outflow: 20
        )
        let simulation = model.simulation(flowScaling: .outflowFirst)

        let adjusted = simulation.adjustFlows(estimated: NumericVector([10, 20]),
                                              stocks: NumericVector([50]))

        #expect(adjusted[0].approxEqual(to: 10))
        #expect(adjusted[1].approxEqual(to: 20))
    }

    @Test func computeNetRatesIsInflowMinusOutflow() throws {
        // Model: ( inflow ) ---> | stock | ---> ( outflow )
        let model = SimulationFixtures.stockWithInflowAndOutflow(
            initialStock: 0,
            inflow: 10,
            outflow: 4
        )
        let simulation = model.simulation()

        let rates = simulation.computeNetRates(flows: NumericVector([10, 4]))

        #expect(rates[0].approxEqual(to: 6))
    }

    @Test func ratesUsesFreshlyEvaluatedFlows() throws {
        // Regression test: `rates` must re-evaluate the flow formulas into its
        // working copy and adjust THOSE estimates. Reading the flows vector of
        // the passed-in state would use the previous step's adjusted values.
        let model = SimulationFixtures.singleStockInflow(
            initialStock: 0,
            inflow: 10
        )
        
        let simulation = model.simulation()
        var state = try simulation.initialize(time: 0, timeDelta: 1)

        state.flows[0] = 999    // stale "adjusted at rest" value

        let (rates, adjusted) = try simulation.rates(state)

        #expect(rates[0].approxEqual(to: 10))
        #expect(adjusted[0].approxEqual(to: 10))
    }

    @Test func clampNonNegativeStocksClampsToZero() throws {
        // Model: ( inflow ) ---> | stock |
        let model = SimulationFixtures.singleStockInflow(
            initialStock: 0,
            inflow: 10,
            allowsNegative: false
        )
        
        let simulation = model.simulation()
        var state = try simulation.initialize(time: 0, timeDelta: 1)
        state.stocks[0] = -3

        simulation.clampNonNegativeStocks(in: &state)

        #expect(state.stocks[0] == 0)
    }

    @Test func clampNonNegativeStocksLeavesNegativeAllowedStocks() throws {
        // Model: ( inflow ) ---> | stock |
        let model = SimulationFixtures.singleStockInflow(
            initialStock: 0,
            inflow: 10,
            allowsNegative: true
        )
        
        let simulation = model.simulation()
        var state = try simulation.initialize(time: 0, timeDelta: 1)
        state.stocks[0] = -3

        simulation.clampNonNegativeStocks(in: &state)

        #expect(state.stocks[0].approxEqual(to: -3))
    }

    @Test func eulerStepShiftsEstimatedFlowToNumerics() throws {
        // Model: | stock | ---> ( outflow )
        // Shared end-of-step convention: the flows vector holds the ADJUSTED
        // value, the estimated value is preserved in numerics.
        let model = SimulationFixtures.singleStockOutflow(
            initialStock: 5,
            outflow: 10
        )
        let simulation = model.simulation(solver: .euler)

        let state = try run(simulation, steps: 1, dt: 1.0)

        #expect(state.stocks[0] == 0)
        #expect(state.flows[0].approxEqual(to: 5))     // adjusted flow at rest
        #expect(state.numerics[0].approxEqual(to: 10)) // estimate moved to numerics
    }

    @Test func adjustFlowsDoesNotDrainEmptyStock() throws {
        // Model: | stock | ---> ( outflow )
        // An empty non-negative stock must not be able to drain anything.
        let model = SimulationFixtures.singleStockOutflow(
            initialStock: 0,
            outflow: 10
        )
        let simulation = model.simulation(flowScaling: .outflowFirst)

        let adjusted = simulation.adjustFlows(estimated: NumericVector([10]),
                                              stocks: NumericVector([0]))

        #expect(adjusted[0] == 0)
    }

    @Test func adjustFlowsInflowFirstUsesAdjustedInflow() throws {
        // A -> B -> cloud, inflowFirst. The inflow into B is the flow A -> B,
        // which is constrained by A. B's outflow must be limited by the
        // adjusted inflow, not by the raw estimate.
        let aID = ObjectID(intValue: 1)
        let bID = ObjectID(intValue: 2)
        let abID = ObjectID(intValue: 3)
        let outID = ObjectID(intValue: 4)

        let plan = SimulationFixtures.makePlan(
            stocks: [
                SimulationFixtures.Stock(aID, name: "a", initialValue: 5),
                SimulationFixtures.Stock(bID, name: "b", initialValue: 0),
            ],
            flows: [
                SimulationFixtures.Flow(abID, name: "a_to_b", value: 10,
                                        fills: bID, drains: aID),
                SimulationFixtures.Flow(outID, name: "out", value: 8,
                                        drains: bID),
            ]
        )
        let simulation = StockFlowSimulation(plan, flowScaling: .inflowFirst)

        let adjusted = simulation.adjustFlows(estimated: NumericVector([10, 8]),
                                              stocks: NumericVector([5, 0]))

        #expect(adjusted[0].approxEqual(to: 5))   // A -> B scaled by A's stock
        #expect(adjusted[1].approxEqual(to: 5))   // B -> cloud scaled by adjusted inflow
    }
}
