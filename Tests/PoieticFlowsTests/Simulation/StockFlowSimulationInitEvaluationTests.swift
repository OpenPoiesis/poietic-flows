//
//  StockFlowSimulationInitEvaluationTests.swift
//  PoieticFlows
//
//  Tests for state initialisation and object evaluation.
//
//  Fixtures are defined in SimulationFixtures.swift.
//
//  NOTE: These tests were written with agent assistance, reviewed and validated by a human.


// IMPORTANT: If the layout of the state changes, then state indices below must be updated.

import Testing
import Foundation
@testable import PoieticCore
@testable import PoieticFlows

@Suite struct StockFlowSimulationInitEvaluationTests {

    @Test func initInDependencyOrder() throws {
        // aux = 5, flow = aux * 2. The flow must see the evaluated auxiliary.
        let model = SimulationFixtures.auxFlow(auxValue: 5)
        let simulation = model.simulation()

        let state = try simulation.initialize(time: 0, timeDelta: 1)

        #expect(state.numerics[0].approxEqual(to: 5))   // auxiliary value
        #expect(state.flows[0].approxEqual(to: 10))     // flow = aux * 2
        #expect(state.stocks[0] == 0)
    }

    @Test func parameterizedFlowBecomesConstant() throws {
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation()
        let flowID = try #require(model.flowIDs.first)

        var state = try simulation.initialize(time: 0,
                                              timeDelta: 1,
                                              parameters: [flowID: Variant(7)])
        #expect(state.flows[0].approxEqual(to: 7))

        state = try simulation.step(state)
        #expect(state.stocks[0].approxEqual(to: 7))      // stock advanced by the constant
        #expect(state.flows[0].approxEqual(to: 7))       // constant preserved
    }

    @Test func parameterizedStockIsNotConstant() throws {
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation()

        var state = try simulation.initialize(time: 0,
                                              timeDelta: 1,
                                              parameters: [model.stockID: Variant(5)])
        #expect(state.stocks[0] == 5)

        state = try simulation.step(state)
        #expect(state.stocks[0].approxEqual(to: 15))     // still integrates
    }

    @Test func unknownParameterThrows() throws {
        let model = SimulationFixtures.singleStockInflow()
        let simulation = model.simulation()
        let unknownID = ObjectID(intValue: 999)

        do {
            _ = try simulation.initialize(time: 0,
                                          timeDelta: 1,
                                          parameters: [unknownID: Variant(1)])
            Issue.record("Expected SimulationError.unknownObject")
        } catch let error {
            guard case .unknownObject = error else {
                Issue.record("Expected .unknownObject, got \(error)")
                return
            }
        }
    }

    @Test func evaluateWritesObjectValue() throws {
        let model = SimulationFixtures.auxFlow(auxValue: 5)
        let simulation = model.simulation()
        var state = try simulation.initialize(time: 0, timeDelta: 1)

        state.numerics[0] = 0
        let auxID = try #require(model.auxID)
        let aux = try #require(model.plan.simulationObjects.first { $0.objectID == auxID })

        try simulation.evaluate(object: aux, in: &state)

        #expect(state.numerics[0].approxEqual(to: 5))
    }

    @Test func updateAuxiliariesAndFlowsSkipsConstants() throws {
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation()
        let flowID = try #require(model.flowIDs.first)

        var state = try simulation.initialize(time: 0,
                                              timeDelta: 1,
                                              parameters: [flowID: Variant(7)])

        // A constant must survive re-evaluation untouched.
        state.flows[0] = 99
        try simulation.updateAuxiliariesAndFlows(in: &state)

        #expect(state.flows[0].approxEqual(to: 99))
    }

    @Test
    func initializeCopiesFlowEstimateToNumerics() throws {
        // Row 0 convention: the flow column and the estimated column should
        // both carry the initial estimate.
        let model = SimulationFixtures.singleStockInflow(initialStock: 0, inflow: 10)
        let simulation = model.simulation()

        let state = try simulation.initialize(time: 0, timeDelta: 1)

        #expect(state.flows[0].approxEqual(to: 10))
        #expect(state.numerics[0].approxEqual(to: 10))
    }
}
