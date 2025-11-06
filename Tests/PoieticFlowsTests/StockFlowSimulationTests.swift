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
    let design: Design
    let frame: TransientFrame
    var plan: SimulationPlan!
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }
    
    mutating func compile() throws {
        let compiler = Compiler(frame: try design.accept(frame))
        self.plan = try compiler.compile()
    }
    
    func index(_ object: TransientObject) -> SimulationState.Index {
        plan.variableIndex(of: object.objectID)!
    }
    
    @Test mutating func initializeStocks() throws {
        let c = frame.createNode(ObjectType.Stock, name: "const", attributes: ["formula": "100"])
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "1"])
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        #expect(state[index(c)] == 100)
        #expect(state[index(a)] == 1)
    }
    
    @Test mutating func testEverythingInitialized() throws {
        let aux = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "10"])
        let stock = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "20"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "c", attributes: ["formula": "30"])
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        #expect(state[index(aux)] == 10)
        #expect(state[index(stock)] == 20)
        #expect(state[index(flow)] == 30)
    }
    
    @Test mutating func initializeOverride() throws {
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "10"])
        let b = frame.createNode(ObjectType.Auxiliary, name: "b", attributes: ["formula": "20"])
        let c = frame.createNode(ObjectType.Auxiliary, name: "c", attributes: ["formula": "a - 1"])
        frame.createEdge(ObjectType.Parameter, origin: a.objectID, target: c.objectID)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        
        let overrides: [ObjectID:Variant] = [
            a.objectID: Variant(999),
        ]
        let state = try sim.initialize(override: overrides)
        
        #expect(state[index(a)] == 999)
        #expect(state[index(b)] == 20)
        #expect(state[index(c)] == 998)
    }
    
    @Test mutating func timeDependentExpression() throws {
        let a_time = frame.createNode(ObjectType.Auxiliary, name: "a_time", attributes: ["formula": "time"])
        let f_time = frame.createNode(ObjectType.FlowRate, name: "f_time", attributes: ["formula": "time * 10"])
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize(time: 1.0)
        
        #expect(state[index(a_time)] == 1.0)
        #expect(state[index(f_time)] == 10.0)
        
        let state2 = try sim.step(state)
        #expect(state2[index(a_time)] == 2.0)
        #expect(state2[index(f_time)] == 20.0)
        
        let state3 = try sim.step(state2)
        #expect(state3[index(a_time)] == 3.0)
        #expect(state3[index(f_time)] == 30.0)
    }
    
    @Test mutating func estimatedFlows() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "0", "allows_negative": true])
        let inflow = frame.createNode(.FlowRate, name: "inflow", attributes: ["formula": "10"])
        let outflow = frame.createNode(.FlowRate, name: "outflow", attributes: ["formula": "20"])
        frame.createEdge(.Flow, origin: stock, target: outflow)
        frame.createEdge(.Flow, origin: inflow, target: stock)
        try compile()
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let flows = sim.flows(state)
        #expect(flows.count == 2)
        #expect(flows[plan.flowIndex(inflow.objectID)] == 10.0)
        #expect(flows[plan.flowIndex(outflow.objectID)] == 20.0)
        let estimated = sim.adjustFlows(flows: flows, stocks: sim.stocks(state))
        #expect(estimated[plan.flowIndex(inflow.objectID)] == 10.0)
        #expect(estimated[plan.flowIndex(outflow.objectID)] == 20.0)
    }

    @Test mutating func adjustedNonNegativeFlowsOutflowFirst() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "12", "allows_negative": false])
        let inflow = frame.createNode(.FlowRate, name: "inflow", attributes: ["formula": "100"])
        let out1 = frame.createNode(.FlowRate, name: "out1", attributes: ["formula": "10"])
        let out2 = frame.createNode(.FlowRate, name: "out2", attributes: ["formula": "20"])
        frame.createEdge(.Flow, origin: inflow, target: stock)
        frame.createEdge(.Flow, origin: stock, target: out1)
        frame.createEdge(.Flow, origin: stock, target: out2)
        try compile()
        let sim = StockFlowSimulation(plan, flowScaling: .outflowFirst)
        let state = try sim.initialize()
        let flows = sim.flows(state)
        #expect(flows.count == 3)
        #expect(flows[plan.flowIndex(inflow.objectID)] == 100.0)
        #expect(flows[plan.flowIndex(out1.objectID)] == 10.0)
        #expect(flows[plan.flowIndex(out2.objectID)] == 20.0)
        let adjusted = sim.adjustFlows(flows: flows, stocks: sim.stocks(state))
        #expect(adjusted[plan.flowIndex(out1.objectID)] == 4.0)
        #expect(adjusted[plan.flowIndex(out2.objectID)] == 8.0)
        
        let delta = sim.computeDerivatives(flows: adjusted, stocks: sim.stocks(state), timeDelta: state.timeDelta)
        #expect(delta[plan.stockIndex(stock.objectID)] == 100 - 4.0 - 8.0)
    }

    @Test mutating func adjustedNonNegativeFlowsInflowFirst() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "10", "allows_negative": false])
        let inflow = frame.createNode(.FlowRate, name: "inflow", attributes: ["formula": "2"])
        let out1 = frame.createNode(.FlowRate, name: "out1", attributes: ["formula": "10"])
        let out2 = frame.createNode(.FlowRate, name: "out2", attributes: ["formula": "20"])
        frame.createEdge(.Flow, origin: inflow, target: stock)
        frame.createEdge(.Flow, origin: stock, target: out1)
        frame.createEdge(.Flow, origin: stock, target: out2)
        try compile()
        let sim = StockFlowSimulation(plan, flowScaling: .inflowFirst)
        let state = try sim.initialize()

        let flows = sim.flows(state)
        #expect(flows.count == 3)
        #expect(flows[plan.flowIndex(inflow.objectID)] == 2.0)
        #expect(flows[plan.flowIndex(out1.objectID)] == 10.0)
        #expect(flows[plan.flowIndex(out2.objectID)] == 20.0)

        let adjusted = sim.adjustFlows(flows: flows, stocks: sim.stocks(state))
        #expect(adjusted[plan.flowIndex(out1.objectID)] == 4.0)
        #expect(adjusted[plan.flowIndex(out2.objectID)] == 8.0)

        let delta = sim.computeDerivatives(flows: adjusted, stocks: sim.stocks(state), timeDelta: state.timeDelta)
        #expect(delta[plan.stockIndex(stock.objectID)] == 2.0 - 4.0 - 8.0)
    }

    @Test mutating func allowsNegativeStock() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "10", "allows_negative": true])
        let inflow = frame.createNode(.FlowRate, name: "inflow", attributes: ["formula": "100"])
        let out1 = frame.createNode(.FlowRate, name: "out1", attributes: ["formula": "200"])
        let out2 = frame.createNode(.FlowRate, name: "out2", attributes: ["formula": "400"])
        frame.createEdge(.Flow, origin: inflow, target: stock)
        frame.createEdge(.Flow, origin: stock, target: out1)
        frame.createEdge(.Flow, origin: stock, target: out2)
        try compile()
        let sim = StockFlowSimulation(plan, flowScaling: .inflowFirst)
        let state = try sim.initialize()

        let flows = sim.flows(state)
        #expect(flows[plan.flowIndex(out1.objectID)] == 200.0)
        #expect(flows[plan.flowIndex(out2.objectID)] == 400.0)

        let adjusted = sim.adjustFlows(flows: flows, stocks: sim.stocks(state))
        #expect(adjusted[plan.flowIndex(out1.objectID)] == 200.0)
        #expect(adjusted[plan.flowIndex(out2.objectID)] == 400.0)

        let delta = sim.computeDerivatives(flows: adjusted, stocks: sim.stocks(state), timeDelta: state.timeDelta)
        #expect(delta[plan.stockIndex(stock.objectID)] == 100.0 - 200.0 - 400.0)
    }

    @Test mutating func diffTimeDelta() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "15", "allows_negative": false])
        let inflow = frame.createNode(.FlowRate, name: "inflow", attributes: ["formula": "100"])
        let out1 = frame.createNode(.FlowRate, name: "out1", attributes: ["formula": "10"])
        let out2 = frame.createNode(.FlowRate, name: "out2", attributes: ["formula": "20"])
        frame.createEdge(.Flow, origin: inflow, target: stock)
        frame.createEdge(.Flow, origin: stock, target: out1)
        frame.createEdge(.Flow, origin: stock, target: out2)
        try compile()
        let sim = StockFlowSimulation(plan, flowScaling: .outflowFirst)
        let state = try sim.initialize(timeDelta: 0.5)
        let flows = sim.flows(state)
        #expect(flows[plan.flowIndex(inflow.objectID)] == 100.0)
        #expect(flows[plan.flowIndex(out1.objectID)] == 10.0)
        #expect(flows[plan.flowIndex(out2.objectID)] == 20.0)
        let adjusted = sim.adjustFlows(flows: flows, stocks: sim.stocks(state))
        #expect(adjusted[plan.flowIndex(out1.objectID)] == 5.0)
        #expect(adjusted[plan.flowIndex(out2.objectID)] == 10.0)
        
        let delta = sim.computeDerivatives(flows: adjusted, stocks: sim.stocks(state), timeDelta: state.timeDelta)
        #expect(delta[plan.stockIndex(stock.objectID)] == 0.5 * (100.0 - 5.0 - 10.0))
    }

    @Test mutating func allowNegativeStockIntegrated() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "5",
                                                  "allows_negative": true])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[index(stock)] == -5)
    }
    
    @Test mutating func nonNegativeStock() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "5",
                                                  "allows_negative": false])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[index(stock)] == 0)
    }
    @Test mutating func cloudOutflow() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "10",
                                                  "allows_negative": false])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "100"])
        let cloud = frame.createNode(.Cloud, name: "cloud")

        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cloud)

        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[index(stock)] == 0)
    }
    @Test mutating func cloudInflow() throws {
        let stock = frame.createNode(.Stock, name: "stock",
                                     attributes: ["formula": "0",
                                                  "allows_negative": false])
        let flow = frame.createNode(.FlowRate, name: "flow", attributes: ["formula": "100"])
        let cloud = frame.createNode(.Cloud, name: "cloud")

        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
        frame.createEdge(ObjectType.Flow, origin: cloud, target: flow)

        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let result = try sim.step(state)
        
        #expect(result[index(stock)] == 100)
    }


    // TODO: Negative flow is allowed only in bi-directional flow
//    @Test mutating func nonNegativeStockNegativeInflow() throws {
//        let stock = frame.createNode(ObjectType.Stock, name: "stock",
//                                     attributes: ["formula": "5", "allows_negative": false])
//        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "0 - 10"])
//        
//        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
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
//        let stock = frame.createNode(ObjectType.Stock, name: "stock",
//                                     attributes: ["formula": "5", "allows_negative": false])
//        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "-10"])
//        
//        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
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
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state2 = try sim.step(state)
        #expect(state2[index(a)] == 4.0)
        #expect(state2[index(b)] == 8.0)

    }
    @Test mutating func compute() throws {
        let kettle = frame.createNode(ObjectType.Stock, name: "kettle", attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "pour", attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock, name: "cup", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: kettle, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cup)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let state2 = try sim.step(state)
        #expect(state2[index(kettle)] == 900.0 )
        #expect(state2[index(cup)] == 100.0)
        
        let state3 = try sim.step(state2)
        #expect(state3[index(kettle)] == 800.0 )
        #expect(state3[index(cup)] == 200.0)
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
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        #expect(state[index(g1)] == 0.0)
        #expect(state[index(g2)] == 10.0)
        #expect(state[index(aux)] == 10.0)
    }
    
    // Other tests - that should rather be at lower level
    
    @Test mutating func builtinFunctionIf() throws {
        // TODO: This should be tested at expression evaluation level
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "a",
                                   attributes: ["formula": "if(time < 2, 0, 1)"])
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        #expect(state[index(aux)] == 0.0)
        
        let state1 = try sim.step(state)
        #expect(state1[index(aux)] == 0.0)
        
        let state2 = try sim.step(state1)
        #expect(state2[index(aux)] == 1.0)
        
        let state3 = try sim.step(state2)
        #expect(state3[index(aux)] == 1.0)
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

        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        // Init 0
        #expect(state.double(at: index(delay0)) == 0.0)
        #expect(state.double(at: index(delay1)) == 0.0)
        #expect(state.double(at: index(delay3)) == 0.0)

        // Step 1
        let state1 = try sim.step(state)
        #expect(state1[index(delay0)] == 10.0)
        #expect(state1[index(delay1)] == 0.0)
        #expect(state1[index(delay3)] == 0.0)

        // Step 2
        let state2 = try sim.step(state1)
        #expect(state2[index(delay0)] == 10.0)
        #expect(state2[index(delay1)] == 10.0)
        #expect(state2[index(delay3)] == 0.0)

        // Step 3
        let state3 = try sim.step(state2)
        #expect(state3[index(delay0)] == 10.0)
        #expect(state3[index(delay1)] == 10.0)
        #expect(state3[index(delay3)] == 0.0)

        // Step 4
        let state4 = try sim.step(state3)
        #expect(state4[index(delay0)] == 10.0)
        #expect(state4[index(delay1)] == 10.0)
        #expect(state4[index(delay3)] == 10.0)
    }
    
    @Test mutating func divByZeroFlow() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "1 / 0"])
        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state1 = try sim.step(state)
        #expect(state1[index(stock)].isInfinite)
    }
    
    @Test mutating func stockCycle() throws {
        let a = frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "10"])
        let b = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        let atob = frame.createNode(ObjectType.FlowRate, name: "a_to_b", attributes: ["formula": "2"])
        let btoa = frame.createNode(ObjectType.FlowRate, name: "b_to_a", attributes: ["formula": "1"])
        frame.createEdge(.Flow, origin: a, target: atob)
        frame.createEdge(.Flow, origin: atob, target: b)
        frame.createEdge(.Flow, origin: b, target: btoa)
        frame.createEdge(.Flow, origin: btoa, target: a)
        try compile()
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        let state1 = try sim.step(state)
        #expect(state1[index(a)] == 8.0)
        #expect(state1[index(b)] == 2.0)

        let state2 = try sim.step(state1)
        #expect(state2[index(a)] == 7.0)
        #expect(state2[index(b)] == 3.0)

    }
}
