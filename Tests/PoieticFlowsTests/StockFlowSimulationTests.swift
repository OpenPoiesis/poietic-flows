//
//  StockFlowSimulationTests.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

// TODO: Store negative initial value in non-negative stock
// TODO: Tests for very small/large time deltas
// TODO: Tests with mixed value types (Int vs Double)
// TODO: Tests for initialisation with invalid overrides
// TODO: Tests for negative inflow (is outflow) and negative outflow (is inflow)

import Testing
@testable import PoieticFlows
@testable import PoieticCore


@Suite struct TestStockFlowSimulation {
    let solverType: StockFlowSimulation.SolverType
    let design: Design
    let frame: TransientPlane
    let world: World

    init() throws {
        self.solverType = .euler
        self.design = Design(metamodel: StockFlowMetamodel)
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
    throws (SimulationError) -> SimulationState
    {
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

    // FIXME: Remove once the new tests are validated
    @Test mutating func initializeStocks() throws {
        let c = frame.createNode(ObjectType.Stock, name: "const", attributes: ["formula": "100"])
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "1"])
        
        let plan = try self.accept()

        let simulation = StockFlowSimulation(plan)
        let state = try simulation.initialize()

        #expect(state[plan.variableReference(c.objectID)!] == 100)
        #expect(state[plan.variableReference(a.objectID)!] == 1)
    }
    
    // FIXME: Remove once the new tests are validated
    @Test mutating func testEverythingInitialized() throws {
        let aux = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "10"])
        let stock = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "20"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "c", attributes: ["formula": "30"])
        
        let plan = try self.accept()
        let simulation = StockFlowSimulation(plan)
        let state = try simulation.initialize()

        #expect(state[plan.variableReference(aux)!] == 10)
        #expect(state[plan.variableReference(stock)!] == 20)
        #expect(state[plan.variableReference(flow)!] == 30)
    }
    
    // FIXME: Remove once the new tests are validated
    @Test mutating func initializeWithParams() throws {
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "10"])
        let b = frame.createNode(ObjectType.Auxiliary, name: "b", attributes: ["formula": "20"])
        let c = frame.createNode(ObjectType.Auxiliary, name: "c", attributes: ["formula": "a - 1"])
        frame.createEdge(ObjectType.Parameter, origin: a.objectID, target: c.objectID)
        
        let plan = try self.accept()

        let params = ScenarioParameters(
            values: [a.objectID: 999.0]
        )
        let simulation = StockFlowSimulation(plan)
        let state = try simulation.initialize(parameters: params.values)

        #expect(state[plan.variableReference(a)!] == 999)
        #expect(state[plan.variableReference(b)!] == 20)
        #expect(state[plan.variableReference(c)!] == 998)
    }

    // FIXME: Remove once the new tests are validated
    @Test mutating func parameterStaysConstant() throws {
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "time"])
        let b = frame.createNode(ObjectType.Auxiliary, name: "b", attributes: ["formula": "a * 10"])
        frame.createEdge(ObjectType.Parameter, origin: a.objectID, target: b.objectID)
        
        let plan = try self.accept()

        let params = ScenarioParameters(
            values: [b.objectID: 999.0]
        )
        let simulation = StockFlowSimulation(plan)
        let state0 = try simulation.initialize(parameters: params.values)
        
        #expect(state0[plan.variableReference(a)!] == 0)
        #expect(state0[plan.variableReference(b)!] == 999)

        let state1 = try simulation.step(state0)
        
        #expect(state1[plan.variableReference(a)!] == 1)
        #expect(state1[plan.variableReference(b)!] == 999.0)
    }

    // FIXME: Remove once the new tests are validated
    @Test mutating func stockParameterIsNotConstant() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock", attributes: ["formula": "100"])
        let inflow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "10"])
        frame.createEdge(ObjectType.Flow, origin: inflow.objectID, target: stock.objectID)
        
        let plan = try self.accept()

        let params = ScenarioParameters(
            values: [stock.objectID: 200.0]
        )
        let simulation = StockFlowSimulation(plan)
        let state0 = try simulation.initialize(parameters: params.values)

        #expect(state0[plan.variableReference(stock)!] == 200)
        #expect(state0[plan.variableReference(inflow)!] == 10)

        let state1 = try simulation.step(state0)
        
        #expect(state1[plan.variableReference(stock)!] == 210)
        #expect(state1[plan.variableReference(inflow)!] == 10)
    }

    
    @Test mutating func timeDependentExpression() throws {
        let t = frame.createNode(ObjectType.Auxiliary, name: "t", attributes: ["formula": "time"])
        
        let plan = try self.accept()
        let state = try self.run(plan, settings: SimulationSettings(initialTime: 1.0, endTime: 1.0))

        #expect(state[plan.variableReference(t)!] == 1.0)
        
        let state2 = try self.run(plan, settings: SimulationSettings(initialTime: 1.0, timeDelta: 10.0, endTime: 21.0))

        #expect(state2[plan.variableReference(t)!] == 21.0)
    }
    
    // FIXME: Remove once the new tests are validated
    @Test mutating func allowNegativeStockIntegrated() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "5",
                                                  "allows_negative": true])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[plan.variableReference(stock)!] == -5)
    }
    
    // FIXME: Remove once the new tests are validated
    @Test mutating func nonNegativeStock() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "5",
                                                  "allows_negative": false])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[plan.variableReference(stock)!] == 0)
    }
    @Test mutating func cloudOutflow() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "10",
                                                  "allows_negative": false])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "100"])
        let cloud = frame.createNode(.Cloud, name: "cloud")

        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cloud)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[plan.variableReference(stock)!] == 0)
    }
    @Test mutating func cloudInflow() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "0",
                                                  "allows_negative": false])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "100"])
        let cloud = frame.createNode(.Cloud, name: "cloud")

        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
        frame.createEdge(ObjectType.Flow, origin: cloud, target: flow)

        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[plan.variableReference(stock)!] == 100)
    }


    // TODO: Negative flow is allowed only in bi-directional flow
//    @Test mutating func nonNegativeStockNegativeInflow() throws {
//        let stock = plane.createNode(ObjectType.Stock, name: "stock",
//                                     attributes: ["formula": "5", "allows_negative": false])
//        let flow = plane.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "0 - 10"])
//        
//        plane.createEdge(ObjectType.Flow, origin: flow, target: stock)
//        
//        try compile()
//        
//        let sim = StockFlowSimulation(plan)
//        var state = try sim.initialize()
//        
//        let diff = sim.stockDifference(state: &state)
//        
//        #expect(diff[plan.stockIndex(stock.id)] == 0)
//    }
//    
//    @Test mutating func stockNegativeOutflow() throws {
//        let stock = plane.createNode(ObjectType.Stock, name: "stock",
//                                     attributes: ["formula": "5", "allows_negative": false])
//        let flow = plane.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "-10"])
//        
//        plane.createEdge(ObjectType.Flow, origin: stock, target: flow)
//        
//        try compile()
//        
//        let sim = StockFlowSimulation(plan)
//        var state = try sim.initialize()
//        
//        let diff = sim.stockDifference(state: &state)
//        
//        #expect(diff[plan.stockIndex(stock.id)] == 0)
//    }
    
    @Test mutating func nonNegativeToTwo() throws {
        let source = frame.createNode(.Stock, name: "stock",
                                      attributes: ["formula": "12", "allows_negative": false])
        
        let a = frame.createNode(.Stock, name: "a", attributes: ["formula": "0"])
        let b = frame.createNode(.Stock, name: "b", attributes: ["formula": "0"])
        let aRate = frame.createNode(.FlowRate, name: "a_rate", attributes: ["formula": "10"])
        let bRate = frame.createNode(.FlowRate, name: "b_rate", attributes: ["formula": "20"])

        frame.createEdge(.Flow, origin: source, target: aRate)
        frame.createEdge(.Flow, origin: aRate, target: a)
        frame.createEdge(.Flow, origin: source, target: bRate)
        frame.createEdge(.Flow, origin: bRate, target: b)
        
        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state2 = try sim.step(state)
        #expect(state2[plan.variableReference(a)!] == 4.0)
        #expect(state2[plan.variableReference(b)!] == 8.0)

    }
    @Test mutating func compute() throws {
        let kettle = frame.createNode(ObjectType.Stock, name: "kettle", attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "pour", attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock, name: "cup", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: kettle, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cup)
        
        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let state2 = try sim.step(state)
        #expect(state2[plan.variableReference(kettle)!] == 900.0 )
        #expect(state2[plan.variableReference(cup)!] == 100.0)
        
        let state3 = try sim.step(state2)
        #expect(state3[plan.variableReference(kettle)!] == 800.0 )
        #expect(state3[plan.variableReference(cup)!] == 200.0)
    }
    
    @Test mutating func graphicalFunction() throws {
        let p1 = frame.createNode(ObjectType.Auxiliary, name:"p1", attributes: ["formula": "0"])
        let g1 = frame.createNode(ObjectType.GraphicalFunction, name: "g1")
        let p2 = frame.createNode(ObjectType.Auxiliary, name:"p2", attributes: ["formula": "0"])
        let points = [Point(0.0, 10.0), Point(1.0, 10.0)]
        let g2 = frame.createNode(ObjectType.GraphicalFunction, name: "g2", attributes: ["graphical_function_points": Variant(points)])
        let aux = frame.createNode(ObjectType.Auxiliary, name:"a", attributes: ["formula": "g1 + g2"])
        
        frame.createEdge(ObjectType.Parameter, origin: g1, target: aux)
        frame.createEdge(ObjectType.Parameter, origin: g2, target: aux)
        frame.createEdge(ObjectType.Parameter, origin: p1, target: g1)
        frame.createEdge(ObjectType.Parameter, origin: p2, target: g2)
        
        let plan = try accept()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        #expect(state[plan.variableReference(g1)!] == 0.0)
        #expect(state[plan.variableReference(g2)!] == 10.0)
        #expect(state[plan.variableReference(aux)!] == 10.0)
    }
    
    // Other tests - that should rather be at lower level
    
    @Test mutating func builtinFunctionIf() throws {
        // TODO: This should be tested at expression evaluation level
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "a",
                                   attributes: ["formula": "if(time < 2, 0, 1)"])
        
        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        #expect(state[plan.variableReference(aux)!] == 0.0)
        
        let state1 = try sim.step(state)
        #expect(state1[plan.variableReference(aux)!] == 0.0)
        
        let state2 = try sim.step(state1)
        #expect(state2[plan.variableReference(aux)!] == 1.0)
        
        let state3 = try sim.step(state2)
        #expect(state3[plan.variableReference(aux)!] == 1.0)
    }
    
    @Test mutating func delay() throws {
        let input = frame.createNode(ObjectType.Auxiliary, name: "input", attributes: ["formula": "10"])
        let delay0 = frame.createNode(ObjectType.Delay, name: "delay0",
                                     attributes: [ "delay_duration": 0, "initial_value": 0.0, ])
        let delay1 = frame.createNode(ObjectType.Delay, name: "delay1",
                                     attributes: [ "delay_duration": 1, "initial_value": 0.0, ])
        let delay3 = frame.createNode(ObjectType.Delay, name: "delay3",
                                     attributes: [ "delay_duration": 3, "initial_value": 0.0, ])

        frame.createEdge(ObjectType.Parameter, origin: input, target: delay0)
        frame.createEdge(ObjectType.Parameter, origin: input, target: delay1)
        frame.createEdge(ObjectType.Parameter, origin: input, target: delay3)

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
        let stock = frame.createNode(ObjectType.Stock, name: "stock", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "1 / 0"])
        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
        
        let plan = try accept()

        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state1 = try sim.step(state)
        let value: Double = try state1[plan.variableReference(stock)!].doubleValue()
        #expect(value.isInfinite)
    }
    
    
    @Test(.disabled("Requires investigation and alignment with new integrators"))
    mutating func stockCycle() throws {
        let a = frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "10"])
        let b = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        let atob = frame.createNode(ObjectType.FlowRate, name: "a_to_b", attributes: ["formula": "2"])
        let btoa = frame.createNode(ObjectType.FlowRate, name: "b_to_a", attributes: ["formula": "1"])
        frame.createEdge(.Flow, origin: a, target: atob)
        frame.createEdge(.Flow, origin: atob, target: b)
        frame.createEdge(.Flow, origin: b, target: btoa)
        frame.createEdge(.Flow, origin: btoa, target: a)
        let plan = try accept()
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state1 = try sim.step(state)
        #expect(state1[plan.variableReference(a)!] == 8.0)
        #expect(state1[plan.variableReference(b)!] == 2.0)

        let state2 = try sim.step(state1)
        #expect(state2[plan.variableReference(a)!] == 7.0)
        #expect(state2[plan.variableReference(b)!] == 3.0)

    }
}
