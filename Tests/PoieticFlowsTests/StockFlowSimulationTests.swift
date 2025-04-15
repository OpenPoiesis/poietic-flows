//
//  StockFlowSimulationTests.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

// TODO: Store negative initial value in non-negative stock

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct TestStockFlowSimulation {
    let design: Design
    let frame: TransientFrame
    var plan: SimulationPlan!
    
    init() throws {
        self.design = Design(metamodel: FlowsMetamodel)
        self.frame = design.createFrame()
    }
    
    mutating func compile() throws {
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        self.plan = try compiler.compile()
    }
    
    func index(_ object: MutableObject) -> SimulationState.Index {
        plan.variableIndex(of: object.id)!
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
        frame.createEdge(ObjectType.Parameter, origin: a.id, target: c.id)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        
        let overrides: [ObjectID:Variant] = [
            a.id: Variant(999),
        ]
        let state = try sim.initialize(override: overrides)
        
        #expect(state[index(a)] == 999)
        #expect(state[index(b)] == 20)
        #expect(state[index(c)] == 998)
    }
    
    @Test mutating func stageWithTime() throws {
        let aux = frame.createNode(ObjectType.Auxiliary, name: "aux", attributes: ["formula": "time"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "time * 10"])
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize(time: 1.0)
        
        #expect(state[index(aux)] == 1.0)
        #expect(state[index(flow)] == 10.0)
        
        var state2 = state.advance(time: 2.0)
        state2[plan.timeVariableIndex] = Variant(state2.time)
        try sim.update(&state2)
        #expect(state2[index(aux)] == 2.0)
        #expect(state2[index(flow)] == 20.0)
        
        var state3 = state.advance(time: 10.0)
        state3[plan.timeVariableIndex] = Variant(state3.time)
        try sim.update(&state3)
        #expect(state3[index(aux)] == 10.0)
        #expect(state3[index(flow)] == 100.0)
    }
    
    @Test mutating func allowNegativeStock() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock",
                                     attributes: ["formula": "5", "allows_negative": true])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(stock.id)] == -10)
    }
    
    @Test mutating func nonNegativeStock() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock",
                                     attributes: ["formula": "5", "allows_negative": false])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(stock.id)] == -5)
    }
    // TODO: Also negative outflow
    @Test mutating func nonNegativeStockNegativeInflow() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock",
                                     attributes: ["formula": "5", "allows_negative": false])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "0 - 10"])
        
        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(stock.id)] == 0)
    }
    
    @Test mutating func stockNegativeOutflow() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock",
                                     attributes: ["formula": "5", "allows_negative": false])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "-10"])
        
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(stock.id)] == 0)
    }
    
    @Test mutating func nonNegativeToTwo() throws {
        // TODO: Break this into multiple tests
        let source = frame.createNode(ObjectType.Stock, name: "stock",
                                      attributes: ["formula": "5", "allows_negative": false])
        
        let happy = frame.createNode(ObjectType.Stock, name: "happy", attributes: ["formula": "0"])
        let sad = frame.createNode(ObjectType.Stock, name: "sad", attributes: ["formula": "0"])
        let happyFlow = frame.createNode(ObjectType.FlowRate, name: "happy_flow",
                                         attributes: ["formula": "10", "priority": 1])
        
        frame.createEdge(ObjectType.Flow, origin: source, target: happyFlow)
        frame.createEdge(ObjectType.Flow, origin: happyFlow, target: happy)
        
        let sadFlow = frame.createNode(ObjectType.FlowRate, name: "sad_flow",
                                       attributes: ["formula": "10", "priority": 2])
        
        frame.createEdge(ObjectType.Flow, origin: source, target: sadFlow)
        frame.createEdge(ObjectType.Flow, origin: sadFlow, target: sad)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let initial = try sim.initialize()
        var state = try sim.initialize()
        
        // We require that the stocks will be computed in the following order:
        // 1. source
        // 2. happy
        // 3. sad
        
        // Compute test
        
        #expect(state[index(happyFlow)] == 10)
        #expect(state[index(sadFlow)] == 10)
        
        let sourceStock = try #require(plan.stocks.first(where: {$0.id == source.id}))
        let sourceDiff = sim.computeStockDelta(sourceStock, in: &state)
        // Adjusted flow to actual outflow
        #expect(state[index(happyFlow)] == 5.0)
        #expect(state[index(sadFlow)] == 0.0)
        #expect(sourceDiff == -5.0)
        
        let happyStock = try #require(plan.stocks.first {$0.id == happy.id})
        let happyDiff = sim.computeStockDelta(happyStock, in: &state)
        // Remains the same as above
        #expect(state[index(happyFlow)] == 5.0)
        #expect(state[index(sadFlow)] == 0.0)
        #expect(happyDiff == +5.0)
        
        let sadStock = try #require(plan.stocks.first {$0.id == sad.id})
        let sadDiff = sim.computeStockDelta(sadStock, in: &state)
        // Remains the same as above
        #expect(state[index(happyFlow)] == 5.0)
        #expect(state[index(sadFlow)] == 0.0)
        #expect(sadDiff == 0.0)
        
        let diff = sim.stockDifference(state: initial)
        
        #expect(diff[plan.stockIndex(source.id)] == -5)
        #expect(diff[plan.stockIndex(happy.id)] == +5)
        #expect(diff[plan.stockIndex(sad.id)] == 0)
    }
    
    @Test mutating func difference() throws {
        let kettle = frame.createNode(ObjectType.Stock, name: "kettle", attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "pour", attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock, name: "cup", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: kettle, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cup)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(kettle.id)] == -100.0)
        #expect(diff[plan.stockIndex(cup.id)] == 100.0)
    }
    
    @Test mutating func differenceTimeDelta() throws {
        let kettle = frame.createNode(ObjectType.Stock, name: "kettle", attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "pour", attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock, name: "cup", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: kettle, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cup)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize(timeDelta: 0.5)
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(kettle.id)] == -50.0)
        #expect(diff[plan.stockIndex(cup.id)] == 50.0)
    }
    
    @Test mutating func compute() throws {
        let kettle = frame.createNode(ObjectType.Stock, name: "kettle", attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "pour", attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock, name: "cup", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: kettle, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: cup)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        var state = try sim.initialize()
        
        try sim.update(&state)
        #expect(state[index(kettle)] == 900.0 )
        #expect(state[index(cup)] == 100.0)
        
        try sim.update(&state)
        #expect(state[index(kettle)] == 800.0 )
        #expect(state[index(cup)] == 200.0)
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
        
        var state1 = state.advance()
        state1[plan.timeVariableIndex] = Variant(state1.time)
        try sim.update(&state1)
        #expect(state1[index(aux)] == 0.0)
        
        var state2 = state1.advance()
        state2[plan.timeVariableIndex] = Variant(state2.time)
        try sim.update(&state2)
        #expect(state2[index(aux)] == 1.0)
        
        var state3 = state2.advance()
        state3[plan.timeVariableIndex] = Variant(state3.time)
        try sim.update(&state3)
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
        var state = try sim.initialize()
        
        // Init 0
        #expect(state.double(at: index(delay0)) == 0.0)
        #expect(state.double(at: index(delay1)) == 0.0)
        #expect(state.double(at: index(delay3)) == 0.0)

        // Step 1
        try sim.update(&state)
        #expect(state[index(delay0)] == 10.0)
        #expect(state[index(delay1)] == 0.0)
        #expect(state[index(delay3)] == 0.0)

        // Step 2
        try sim.update(&state)
        #expect(state[index(delay0)] == 10.0)
        #expect(state[index(delay1)] == 10.0)
        #expect(state[index(delay3)] == 0.0)

        // Step 3
        try sim.update(&state)
        #expect(state[index(delay0)] == 10.0)
        #expect(state[index(delay1)] == 10.0)
        #expect(state[index(delay3)] == 0.0)

        // Step 4
        try sim.update(&state)
        #expect(state[index(delay0)] == 10.0)
        #expect(state[index(delay1)] == 10.0)
        #expect(state[index(delay3)] == 10.0)
    }
    
    @Test mutating func nanInflow() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "1 / 0"])
        frame.createEdge(ObjectType.Flow, origin: flow, target: stock)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(stock.id)].isNaN)
    }
    @Test mutating func nanOutflow() throws {
        let stock = frame.createNode(ObjectType.Stock, name: "stock", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "flow", attributes: ["formula": "1 / 0"])
        frame.createEdge(ObjectType.Flow, origin: stock, target: flow)
        
        try compile()
        
        let sim = StockFlowSimulation(plan)
        let state = try sim.initialize()
        
        let diff = sim.stockDifference(state: state)
        
        #expect(diff[plan.stockIndex(stock.id)].isNaN)
    }
}
