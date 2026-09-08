//
//  StockFlowSimulationDesignTests.swift
//  PoieticFlows
//
//  Tests that exercise the simulation through a full design: object creation,
//  planning, and integration. Node-type and error-behaviour tests that are not
//  covered by the fixture-based unit tests in this directory.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct StockFlowSimulationDesignTests {
    let solverType: StockFlowSimulation.SolverType
    let design: Design
    let frame: TransientPlane
    let world: World

    init() throws {
        self.solverType = .euler
        self.design = Design(metamodel: StockFlowDomain.StockFlowMetamodel)
        self.frame = design.createPlane()
        self.world = World(design: design)
        self.world.addSchedule(Schedule(
            label: PlaneChangeSchedule.self,
            systems: SimulationPlanningSystems
        ))
    }

    func accept() throws -> SimulationPlan {
        let accepted = try design.accept(frame)
        world.setPlane(accepted)
        try world.run(schedule: PlaneChangeSchedule.self)
        let plan: SimulationPlan = try #require(world.singleton())
        return plan
    }

    func run(_ plan: SimulationPlan,
             settings: SimulationSettings? = nil,
             parameters: ScenarioParameters? = nil)
    throws (SimulationError) -> SimulationState {
        let settings = settings ?? SimulationSettings()
        let parameters = parameters ?? ScenarioParameters()

        let simulation = StockFlowSimulation(plan, solver: solverType)
        var state = try simulation.initialize(time: settings.initialTime,
                                              timeDelta: settings.timeDelta,
                                              parameters: parameters.values)

        var step: UInt = 1

        while step <= settings.steps {
            let newState = try simulation.step(state)
            state = newState
            step += 1
        }

        return state
    }

    @Test mutating func timeDependentExpression() throws {
        let t = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "t", attributes: ["formula": "time"])

        let plan = try self.accept()
        let state = try self.run(plan, settings: SimulationSettings(initialTime: 1.0,
                                                                    endTime: 1.0))

        #expect(state[plan.variableReference(t)!] == 1.0)

        let state2 = try self.run(plan, settings: SimulationSettings(initialTime: 1.0,
                                                                     timeDelta: 10.0,
                                                                     endTime: 21.0))

        #expect(state2[plan.variableReference(t)!] == 21.0)
    }

    @Test mutating func cloudOutflow() throws {
        let stock = frame.createNode(StockFlowDomain.Types.Stock,
                                     name: "stock",
                                     attributes: ["formula": "10",
                                                  "allows_negative": false])
        let flow = frame.createNode(StockFlowDomain.Types.FlowRate,
                                    name: "flow",
                                    attributes: ["formula": "100"])
        let cloud = frame.createNode(StockFlowDomain.Types.Cloud,
                                     name: "cloud")

        frame.createEdge(StockFlowDomain.Types.Flow, origin: stock, target: flow)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flow, target: cloud)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)

        #expect(result[plan.variableReference(stock)!] == 0)
    }

    @Test mutating func cloudInflow() throws {
        let stock = frame.createNode(StockFlowDomain.Types.Stock,
                                     name: "stock",
                                     attributes: ["formula": "0",
                                                  "allows_negative": false])
        let flow = frame.createNode(StockFlowDomain.Types.FlowRate,
                                    name: "flow",
                                    attributes: ["formula": "100"])
        let cloud = frame.createNode(StockFlowDomain.Types.Cloud,
                                     name: "cloud")

        frame.createEdge(StockFlowDomain.Types.Flow, origin: flow, target: stock)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: cloud, target: flow)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)

        #expect(result[plan.variableReference(stock)!] == 100)
    }

    @Test mutating func nonNegativeToTwo() throws {
        let source = frame.createNode(StockFlowDomain.Types.Stock,
                                      name: "stock",
                                      attributes: ["formula": "12",
                                                   "allows_negative": false])

        let a = frame.createNode(StockFlowDomain.Types.Stock, name: "a", attributes: ["formula": "0"])
        let b = frame.createNode(StockFlowDomain.Types.Stock, name: "b", attributes: ["formula": "0"])
        let aRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "a_rate", attributes: ["formula": "10"])
        let bRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "b_rate", attributes: ["formula": "20"])

        frame.createEdge(StockFlowDomain.Types.Flow, origin: source, target: aRate)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: aRate, target: a)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: source, target: bRate)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: bRate, target: b)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state2 = try sim.step(state)
        #expect(state2[plan.variableReference(a)!] == 4.0)
        #expect(state2[plan.variableReference(b)!] == 8.0)
    }

    @Test mutating func compute() throws {
        let kettle = frame.createNode(StockFlowDomain.Types.Stock, name: "kettle", attributes: ["formula": "1000"])
        let flow = frame.createNode(StockFlowDomain.Types.FlowRate, name: "pour", attributes: ["formula": "100"])
        let cup = frame.createNode(StockFlowDomain.Types.Stock, name: "cup", attributes: ["formula": "0"])

        frame.createEdge(StockFlowDomain.Types.Flow, origin: kettle, target: flow)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flow, target: cup)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()

        let state2 = try sim.step(state)
        #expect(state2[plan.variableReference(kettle)!] == 900.0)
        #expect(state2[plan.variableReference(cup)!] == 100.0)

        let state3 = try sim.step(state2)
        #expect(state3[plan.variableReference(kettle)!] == 800.0)
        #expect(state3[plan.variableReference(cup)!] == 200.0)
    }

    @Test mutating func graphicalFunction() throws {
        let p1 = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "p1", attributes: ["formula": "0"])
        let g1 = frame.createNode(StockFlowDomain.Types.GraphicalFunction, name: "g1")
        let p2 = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "p2", attributes: ["formula": "0"])
        let points = [Point(0.0, 10.0), Point(1.0, 10.0)]
        let g2 = frame.createNode(StockFlowDomain.Types.GraphicalFunction, name: "g2",
                                  attributes: ["graphical_function_points": Variant(points)])
        let aux = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "a", attributes: ["formula": "g1 + g2"])

        frame.createEdge(StockFlowDomain.Types.Parameter, origin: g1, target: aux)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: g2, target: aux)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: p1, target: g1)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: p2, target: g2)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()

        #expect(state[plan.variableReference(g1)!] == 0.0)
        #expect(state[plan.variableReference(g2)!] == 10.0)
        #expect(state[plan.variableReference(aux)!] == 10.0)
    }

    @Test mutating func delay() throws {
        let input = frame.createNode(StockFlowDomain.Types.Auxiliary,
                                     name: "input",
                                     attributes: ["formula": "10"])
        let delay0 = frame.createNode(StockFlowDomain.Types.Delay,
                                      name: "delay0",
                                      attributes: [ "delay_duration": 0, "initial_value": 0.0, ])
        let delay1 = frame.createNode(StockFlowDomain.Types.Delay,
                                      name: "delay1",
                                      attributes: [ "delay_duration": 1, "initial_value": 0.0, ])
        let delay3 = frame.createNode(StockFlowDomain.Types.Delay,
                                      name: "delay3",
                                      attributes: [ "delay_duration": 3, "initial_value": 0.0, ])

        frame.createEdge(StockFlowDomain.Types.Parameter, origin: input, target: delay0)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: input, target: delay1)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: input, target: delay3)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()

        // Init 0
        #expect(try state.doubleValue(at: plan.variableReference(delay0)!) == 0.0)
        #expect(try state.doubleValue(at: plan.variableReference(delay1)!) == 0.0)
        #expect(try state.doubleValue(at: plan.variableReference(delay3)!) == 0.0)

        // Step 1
        let state1 = try sim.step(state)
        #expect(state1[plan.variableReference(delay0)!] == 10.0)
        #expect(state1[plan.variableReference(delay1)!] == 0.0)
        #expect(state1[plan.variableReference(delay3)!] == 0.0)

        // Step 2
        let state2 = try sim.step(state1)
        #expect(state2[plan.variableReference(delay0)!] == 10.0)
        #expect(state2[plan.variableReference(delay1)!] == 10.0)
        #expect(state2[plan.variableReference(delay3)!] == 0.0)

        // Step 3
        let state3 = try sim.step(state2)
        #expect(state3[plan.variableReference(delay0)!] == 10.0)
        #expect(state3[plan.variableReference(delay1)!] == 10.0)
        #expect(state3[plan.variableReference(delay3)!] == 0.0)

        // Step 4
        let state4 = try sim.step(state3)
        #expect(state4[plan.variableReference(delay0)!] == 10.0)
        #expect(state4[plan.variableReference(delay1)!] == 10.0)
        #expect(state4[plan.variableReference(delay3)!] == 10.0)
    }

    @Test mutating func divByZeroFlow() throws {
        let stock = frame.createNode(StockFlowDomain.Types.Stock,
                                     name: "stock",
                                     attributes: ["formula": "0"])
        let flow = frame.createNode(StockFlowDomain.Types.FlowRate,
                                    name: "flow",
                                    attributes: ["formula": "1 / 0"])
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flow, target: stock)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state1 = try sim.step(state)
        let value: Double = try state1[plan.variableReference(stock)!].doubleValue()
        #expect(value.isInfinite)
    }
}
