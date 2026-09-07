//
//  SimulationFixtures.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 06/09/2026.
//

import Testing
@testable import PoieticCore
@testable import PoieticFlows

// MARK: - Test model

struct TestModel {
    let plan: SimulationPlan
    let stockID: ObjectID
    let flowIDs: [ObjectID]
    let auxID: ObjectID?

    init(plan: SimulationPlan, stockID: ObjectID, flowIDs: [ObjectID], auxID: ObjectID? = nil) {
        self.plan = plan
        self.stockID = stockID
        self.flowIDs = flowIDs
        self.auxID = auxID
    }

    func simulation(solver: StockFlowSimulation.SolverType = .euler,
                    flowScaling: StockFlowSimulation.FlowScaling = .outflowFirst)
    -> StockFlowSimulation {
        StockFlowSimulation(plan, solver: solver, flowScaling: flowScaling)
    }
}

/// Run a simulation from time 0 for a given number of steps.
func run(_ simulation: StockFlowSimulation,
         steps: Int,
         dt: Double = 1.0,
         parameters: [ObjectID: Variant] = [:]) throws -> SimulationState
{
    var state = try simulation.initialize(time: 0, timeDelta: dt, parameters: parameters)
    for _ in 0..<steps {
        state = try simulation.step(state)
    }
    return state
}

// MARK: - Fixtures

/// Namespace for simulation test fixtures.
///
/// Use ``SimulationFixtures/makePlan(auxiliaries:stocks:flows:)`` to build bespoke
/// simulation plans from semantic model descriptions, and the named factory methods
/// below for the common model shapes.
enum SimulationFixtures {

    // MARK: Model descriptions

    struct Stock {
        let objectID: ObjectID
        let name: String
        let initialValue: Double
        let allowsNegative: Bool

        init(_ objectID: ObjectID, name: String, initialValue: Double, allowsNegative: Bool = false) {
            self.objectID = objectID
            self.name = name
            self.initialValue = initialValue
            self.allowsNegative = allowsNegative
        }
    }

    struct Auxiliary {
        let objectID: ObjectID
        let name: String
        let formula: BoundExpression

        init(_ objectID: ObjectID, name: String, formula: BoundExpression) {
            self.objectID = objectID
            self.name = name
            self.formula = formula
        }

        init(_ objectID: ObjectID, name: String, value: Double) {
            self.init(objectID, name: name, formula: .value(Variant(value)))
        }
    }

    struct Flow {
        let objectID: ObjectID
        let name: String
        let formula: BoundExpression
        let fills: ObjectID?
        let drains: ObjectID?

        init(_ objectID: ObjectID,
             name: String,
             formula: BoundExpression,
             fills: ObjectID? = nil,
             drains: ObjectID? = nil)
        {
            self.objectID = objectID
            self.name = name
            self.formula = formula
            self.fills = fills
            self.drains = drains
        }

        init(_ objectID: ObjectID,
             name: String,
             value: Double,
             fills: ObjectID? = nil,
             drains: ObjectID? = nil)
        {
            self.init(objectID,
                      name: name,
                      formula: .value(Variant(value)),
                      fills: fills,
                      drains: drains)
        }
    }

    // MARK: Plan building

    /// Create a simulation plan from model descriptions.
    ///
    /// The simulation objects are ordered by evaluation dependency: auxiliaries
    /// first (in the order given), then stocks, then flows. Formulas that
    /// reference another object must reference only objects that appear earlier
    /// in that order.
    ///
    /// Numeric state slots are allocated in the same order: auxiliary values
    /// first, then flow estimated values.
    static func makePlan(auxiliaries: [Auxiliary] = [],
                         stocks: [Stock] = [],
                         flows: [Flow] = []) -> SimulationPlan {
        var objects: [SimulationObject] = []
        var variables: [StateVariable] = []
        var boundFlows: [BoundFlow] = []
        var nextNumeric = 0

        for (index, aux) in auxiliaries.enumerated() {
            let object = SimulationObject(
                objectID: aux.objectID,
                computation: .formula(aux.formula),
                variableReference: .numeric(index),
                role: .auxiliary,
                nameKey: aux.name
            )
            objects.append(object)
            variables.append(StateVariable(reference: object.variableReference,
                                           name: aux.name,
                                           content: .object(aux.objectID)))
            nextNumeric += 1
        }

        for (index, stock) in stocks.enumerated() {
            let object = SimulationObject(
                objectID: stock.objectID,
                computation: .formula(.value(Variant(stock.initialValue))),
                variableReference: .stock(index),
                role: .stock,
                nameKey: stock.name
            )
            objects.append(object)
            variables.append(StateVariable(reference: object.variableReference,
                                           name: stock.name,
                                           content: .object(stock.objectID)))
        }

        for (index, flow) in flows.enumerated() {
            let object = SimulationObject(
                objectID: flow.objectID,
                computation: .formula(flow.formula),
                variableReference: .flow(index),
                role: .flow,
                nameKey: flow.name
            )
            objects.append(object)
            variables.append(StateVariable(reference: object.variableReference,
                                           name: flow.name,
                                           content: .object(flow.objectID)))

            let boundFlow = BoundFlow(objectID: flow.objectID,
                                      estimatedNumericIndex: nextNumeric,
                                      drains: flow.drains,
                                      fills: flow.fills)
            boundFlows.append(boundFlow)

            // Estimated flow value slot. This must be part of the state layout
            // so that the simulation state allocates space for it.
            variables.append(StateVariable(reference: .numeric(nextNumeric),
                                           name: "flow_estimated_\(flow.objectID)",
                                           content: .estimated(flow.objectID)))
            nextNumeric += 1
        }

        var boundStocks: [BoundStock] = []
        for stock in stocks {
            var inflows: [Int] = []
            var outflows: [Int] = []
            for (index, flow) in boundFlows.enumerated() {
                if flow.drains == stock.objectID { outflows.append(index) }
                if flow.fills == stock.objectID { inflows.append(index) }
            }
            boundStocks.append(BoundStock(objectID: stock.objectID,
                                          allowsNegative: stock.allowsNegative,
                                          inflows: inflows,
                                          outflows: outflows))
        }

        return SimulationPlan(
            simulationObjects: objects,
            stateVariables: variables,
            stocks: boundStocks,
            flows: boundFlows
        )
    }

    // MARK: Named models

    /// One stock with one constant flow filling it.
    ///
    ///     ( inflow ) ---> | stock |
    ///
    static func singleStockInflow(initialStock: Double = 0,
                                  inflow: Double = 10,
                                  allowsNegative: Bool = false) -> TestModel {
        let stockID = ObjectID(intValue: 1)
        let flowID = ObjectID(intValue: 2)

        let plan = makePlan(
            stocks: [
                Stock(stockID, name: "stock", initialValue: initialStock, allowsNegative: allowsNegative),
            ],
            flows: [
                Flow(flowID, name: "inflow", value: inflow, fills: stockID),
            ]
        )

        return TestModel(plan: plan, stockID: stockID, flowIDs: [flowID])
    }

    /// One stock with one constant flow draining it.
    ///
    ///     | stock | ---> ( outflow )
    ///
    static func singleStockOutflow(initialStock: Double,
                                   outflow: Double,
                                   allowsNegative: Bool = false) -> TestModel {
        let stockID = ObjectID(intValue: 1)
        let flowID = ObjectID(intValue: 2)

        let plan = makePlan(
            stocks: [
                Stock(stockID, name: "stock", initialValue: initialStock, allowsNegative: allowsNegative),
            ],
            flows: [
                Flow(flowID, name: "outflow", value: outflow, drains: stockID),
            ]
        )

        return TestModel(plan: plan, stockID: stockID, flowIDs: [flowID])
    }

    /// One stock with a constant inflow and a constant outflow.
    ///
    ///     ( inflow ) ---> | stock | ---> ( outflow )
    ///
    /// Used to test `adjustFlows` and `computeNetRates` with two flows.
    static func stockWithInflowAndOutflow(initialStock: Double,
                                          inflow: Double,
                                          outflow: Double) -> TestModel {
        let stockID = ObjectID(intValue: 1)
        let inflowID = ObjectID(intValue: 2)
        let outflowID = ObjectID(intValue: 3)

        let plan = makePlan(
            stocks: [
                Stock(stockID, name: "stock", initialValue: initialStock),
            ],
            flows: [
                Flow(inflowID, name: "inflow", value: inflow, fills: stockID),
                Flow(outflowID, name: "outflow", value: outflow, drains: stockID),
            ]
        )

        return TestModel(plan: plan, stockID: stockID, flowIDs: [inflowID, outflowID])
    }

    /// One stock whose inflow equals the stock itself: dy/dt = y.
    ///
    /// Used for exponential growth tests against the analytic solution.
    static func exponential(initialStock: Double = 1.0) -> TestModel {
        let stockID = ObjectID(intValue: 1)
        let flowID = ObjectID(intValue: 2)

        let flowFormula = BoundExpression.variable(
            BoundVariable(reference: .stock(0), valueType: .double)
        )

        let plan = makePlan(
            stocks: [
                Stock(stockID, name: "stock", initialValue: initialStock),
            ],
            flows: [
                Flow(flowID, name: "growth", formula: flowFormula, fills: stockID),
            ]
        )

        return TestModel(plan: plan, stockID: stockID, flowIDs: [flowID])
    }

    /// One stock, one auxiliary with a constant value, and one flow that is
    /// twice the auxiliary. Used for initialisation/evaluation tests.
    static func auxFlow(auxValue: Double = 5.0) -> TestModel {
        let stockID = ObjectID(intValue: 1)
        let flowID = ObjectID(intValue: 2)
        let auxID = ObjectID(intValue: 3)

        // The auxiliary is allocated in the first numeric slot: .numeric(0).
        let flowFormula = BoundExpression.binary(
            .multiply,
            .variable(BoundVariable(reference: .numeric(0), valueType: .double)),
            .value(Variant(2))
        )

        let plan = makePlan(
            auxiliaries: [
                Auxiliary(auxID, name: "aux", value: auxValue),
            ],
            stocks: [
                Stock(stockID, name: "stock", initialValue: 0),
            ],
            flows: [
                Flow(flowID, name: "flow", formula: flowFormula, fills: stockID),
            ]
        )

        return TestModel(plan: plan, stockID: stockID, flowIDs: [flowID], auxID: auxID)
    }
}
