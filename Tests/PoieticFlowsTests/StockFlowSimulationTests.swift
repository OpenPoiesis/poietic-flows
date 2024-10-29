//
//  StockFlowSimulationTests.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

import XCTest
@testable import PoieticFlows
@testable import PoieticCore

extension SimulationState {
    public subscript(id: ObjectID) -> Double {
        get {
            let index = model.variableIndex(of: id)!
            return try! values[index].doubleValue()
        }
        set(value) {
            let index = model.variableIndex(of: id)!
            values[index] = Variant(value)
        }
    }
}

final class TestStockFlowSimulation: XCTestCase {
    var design: Design!
    var model: CompiledModel!
    var frame: MutableFrame!
    
    override func setUp() {
        design = Design(metamodel: FlowsMetamodel)
        frame = design.deriveFrame()
    }
    
    func compile() throws {
        let compiler = Compiler(frame: try design.accept(frame))
        self.model = try compiler.compile()
    }
    
    func makeSimulation() throws -> StockFlowSimulation {
        try compile()
        return StockFlowSimulation(model)
    }
    
    func testInitializeStocks() throws {
        
        let a = frame.createNode(ObjectType.Auxiliary,
                                 name: "a",
                                 attributes: ["formula": "1"])
        let b = frame.createNode(ObjectType.Auxiliary,
                                 name: "b",
                                 attributes: ["formula": "a + 1"])
        let c =  frame.createNode(ObjectType.Stock,
                                  name: "const",
                                  attributes: ["formula": "100"])
        let s_a = frame.createNode(ObjectType.Stock,
                                   name: "use_a",
                                   attributes: ["formula": "a"])
        let s_b = frame.createNode(ObjectType.Stock,
                                   name: "use_b",
                                   attributes: ["formula": "b"])
        
        frame.createEdge(ObjectType.Parameter, origin: a, target: b, components: [])
        frame.createEdge(ObjectType.Parameter, origin: a, target: s_a, components: [])
        frame.createEdge(ObjectType.Parameter, origin: b, target: s_b, components: [])
        
        try compile()
        
        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        try sim.initialize(&state)
        
        XCTAssertEqual(state[a], 1)
        XCTAssertEqual(state[b], 2)
        XCTAssertEqual(state[c], 100)
        XCTAssertEqual(state[s_a], 1)
        XCTAssertEqual(state[s_b], 2)
    }
    
    func testOrphanedInitialize() throws {
        
        let a = frame.createNode(ObjectType.Auxiliary,
                                 name: "a",
                                 attributes: ["formula": "1"])
        try compile()
        
        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        XCTAssertNotNil(state[a])
    }
    func testEverythingInitialized() throws {
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "a",
                                   attributes: ["formula": "10"])
        let stock = frame.createNode(ObjectType.Stock,
                                     name: "b",
                                     attributes: ["formula": "20"])
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "c",
                                    attributes: ["formula": "30"])
       
        try compile()
        
        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        XCTAssertEqual(state[aux], 10)
        XCTAssertEqual(state[stock], 20)
        XCTAssertEqual(state[flow], 30)
    }
    
    func testStageWithTime() throws {
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "aux",
                                   attributes: ["formula": "time"])
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "flow",
                                    attributes: ["formula": "time * 10"])
        
        try compile()

        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        state[model.timeVariableIndex] = 1.0

        try sim.initialize(&state)

        XCTAssertEqual(state[aux], 1.0)
        XCTAssertEqual(state[flow], 10.0)
        let context = SimulationContext(step: 1, time: 2.0, timeDelta: 1.0)

        state[model.timeVariableIndex] = 2.0
        print("STATE1: \(state)")
        try sim.update(&state, context: context)
        print("STATE2: \(state)")
        XCTAssertEqual(state[aux], 2.0)
        XCTAssertEqual(state[flow], 20.0)
        
        let context2 = SimulationContext(step: 1, time: 10.0, timeDelta: 1.0)
        state[model.timeVariableIndex] = 10.0
        try sim.update(&state, context: context2)
        XCTAssertEqual(state[aux], 10.0)
        XCTAssertEqual(state[flow], 100.0)
    }
    
    func testNegativeStock() throws {
        let stock = frame.createNode(ObjectType.Stock,
                                     name: "stock",
                                     attributes: ["formula": "5"])
        let node = frame.node(stock)
        node.snapshot["allows_negative"] = Variant(true)
        
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "flow",
                                    attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Drains, origin: stock, target: flow, components: [])
        
        try compile()
        
        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        let diff = try sim.stockDifference(context, state: state, time: 1.0)
        
        XCTAssertEqual(diff[model.stockIndex(stock)], -10)
    }
    
    func testNonNegativeStock() throws {
        let stock = frame.createNode(ObjectType.Stock,
                                     name: "stock",
                                     attributes: ["formula": "5"])
        let node = frame.node(stock)
        node.snapshot["allows_negative"] = Variant(false)
        
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "flow",
                                    attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Drains, origin: stock, target: flow, components: [])
        
        try compile()
        
        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)
        var state = SimulationState(model: model)
        try sim.initialize(&state)
 
        let diff = try sim.stockDifference(context, state: state, time: 1.0)

        XCTAssertEqual(diff[model.stockIndex(stock)], -5)
    }
    // TODO: Also negative outflow
    func testNonNegativeStockNegativeInflow() throws {
        let stock = frame.createNode(ObjectType.Stock,
                                     name: "stock",
                                     attributes: ["formula": "5"])
        let obj = frame.node(stock)
        obj.snapshot["allows_negative"] = Variant(false)
        // FIXME: There is a bug in the expression parser
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "flow",
                                    attributes: ["formula": "0 - 10"])
        
        frame.createEdge(ObjectType.Fills, origin: flow, target: stock, components: [])
        
        try compile()
        
        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)
        var state = SimulationState(model: model)
        try sim.initialize(&state)
 
        let diff = try sim.stockDifference(context, state: state, time: 1.0)

        XCTAssertEqual(diff[model.stockIndex(stock)], 0)
    }
    
    func testStockNegativeOutflow() throws {
        let stock = frame.createNode(ObjectType.Stock,
                                     name: "stock",
                                     attributes: ["formula": "5"])
        let obj = frame.node(stock)
        obj.snapshot["allows_negative"] = Variant(false)
        // FIXME: There is a bug in the expression parser
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "flow",
                                    attributes: ["formula": "-10"])
        
        frame.createEdge(ObjectType.Drains, origin: stock, target: flow, components: [])
        
        try compile()
        
        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)
        var state = SimulationState(model: model)
        try sim.initialize(&state)
 
        let diff = try sim.stockDifference(context, state: state, time: 1.0)

        XCTAssertEqual(diff[model.stockIndex(stock)], 0)
    }
    
    func testNonNegativeToTwo() throws {
        // TODO: Break this into multiple tests
        let source = frame.createNode(ObjectType.Stock,
                                      name: "stock",
                                      attributes: ["formula": "5"])
        let sourceNode = frame.node(source)
        sourceNode.snapshot["allows_negative"] = Variant(false)
        
        let happy = frame.createNode(ObjectType.Stock,
                                     name: "happy",
                                     attributes: ["formula": "0"])
        let sad = frame.createNode(ObjectType.Stock,
                                   name: "sad",
                                   attributes: ["formula": "0"])
        let happyFlow = frame.createNode(ObjectType.Flow,
                                         name: "happy_flow",
                                         attributes: ["formula": "10"])
        let happyFlowNode = frame.node(happyFlow)
        happyFlowNode.snapshot["priority"] = Variant(1)
        
        frame.createEdge(ObjectType.Drains,
                         origin: source, target: happyFlow, components: [])
        frame.createEdge(ObjectType.Fills,
                         origin: happyFlow, target: happy, components: [])
        
        let sadFlow = frame.createNode(ObjectType.Flow,
                                       name: "sad_flow",
                                       attributes: ["formula": "10"])
        let sadFlowNode = frame.node(sadFlow)
        sadFlowNode.snapshot["priority"] = Variant(2)
        
        frame.createEdge(ObjectType.Drains,
                         origin: source, target: sadFlow, components: [])
        frame.createEdge(ObjectType.Fills,
                         origin: sadFlow, target: sad, components: [])
        
        try compile()
        
        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)
        var initial = SimulationState(model: model)
        try sim.initialize(&initial)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        // We require that the stocks will be computed in the following order:
        // 1. source
        // 2. happy
        // 3. sad
        
        // Compute test
        
        XCTAssertEqual(state[happyFlow], 10)
        XCTAssertEqual(state[sadFlow], 10)
        
        let sourceDiff = try sim.computeStockDelta(model.compiledStock(source), in: &state)
        // Adjusted flow to actual outflow
        XCTAssertEqual(state[happyFlow],  5.0)
        XCTAssertEqual(state[sadFlow],    0.0)
        XCTAssertEqual(sourceDiff,         -5.0)
        
        let happyDiff = try sim.computeStockDelta(model.compiledStock(happy), in: &state)
        // Remains the same as above
        XCTAssertEqual(state[happyFlow],  5.0)
        XCTAssertEqual(state[sadFlow],    0.0)
        XCTAssertEqual(happyDiff,          +5.0)
        
        let sadDiff = try sim.computeStockDelta(model.compiledStock(sad),in: &state)
        // Remains the same as above
        XCTAssertEqual(state[happyFlow],  5.0)
        XCTAssertEqual(state[sadFlow],    0.0)
        XCTAssertEqual(sadDiff,             0.0)
        
        let diff = try sim.stockDifference(context, state: initial, time: 1.0)
        
        XCTAssertEqual(diff[model.stockIndex(source)], -5)
        XCTAssertEqual(diff[model.stockIndex(happy)],  +5)
        XCTAssertEqual(diff[model.stockIndex(sad)],     0)
    }
    
    func testDifference() throws {
        let kettle = frame.createNode(ObjectType.Stock,
                                      name: "kettle",
                                      attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "pour",
                                    attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock,
                                   name: "cup",
                                   attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Drains,
                         origin: kettle, target: flow, components: [])
        frame.createEdge(ObjectType.Fills,
                         origin: flow, target: cup, components: [])

        try compile()
        
        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        let diff = try sim.stockDifference(context, state: state, time: 1.0)

        XCTAssertEqual(diff[model.stockIndex(kettle)], -100.0)
        XCTAssertEqual(diff[model.stockIndex(cup)], 100.0)
    }
    
    func testDifferenceTimeDelta() throws {
        let kettle = frame.createNode(ObjectType.Stock,
                                      name: "kettle",
                                      attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "pour",
                                    attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock,
                                   name: "cup",
                                   attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Drains,
                         origin: kettle, target: flow, components: [])
        frame.createEdge(ObjectType.Fills,
                         origin: flow, target: cup, components: [])

        try compile()

        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 0.5)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        let diff = try sim.stockDifference(context, state: state, time: 1.0)

        XCTAssertEqual(diff[model.stockIndex(kettle)], -50.0)
        XCTAssertEqual(diff[model.stockIndex(cup)], 50.0)
    }

    
    func testCompute() throws {
        let kettle = frame.createNode(ObjectType.Stock,
                                      name: "kettle",
                                      attributes: ["formula": "1000"])
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "pour",
                                    attributes: ["formula": "100"])
        let cup = frame.createNode(ObjectType.Stock,
                                   name: "cup",
                                   attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Drains,
                         origin: kettle, target: flow, components: [])
        frame.createEdge(ObjectType.Fills,
                         origin: flow, target: cup, components: [])
        
        try compile()

        let sim = StockFlowSimulation(model)
        let context = SimulationContext(step: 1, time: 1.0, timeDelta: 1)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        try sim.update(&state, context: context)
        XCTAssertEqual(state[kettle], 900.0 )
        XCTAssertEqual(state[cup], 100.0)
        
        try sim.update(&state, context: context)
        XCTAssertEqual(state[kettle], 800.0 )
        XCTAssertEqual(state[cup], 200.0)
    }
    
    
    func testGraphicalFunction() throws {
        let p1 = frame.createNode(ObjectType.Auxiliary,
                                  name:"p1",
                                  attributes: ["formula": "0"])
        let g1 = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g1")
        
        let p2 = frame.createNode(ObjectType.Auxiliary,
                                  name:"p2",
                                  attributes: ["formula": "0"])
        let points = [Point(0.0, 10.0), Point(1.0, 10.0)]
        let g2 = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g2",
                                  attributes: ["graphical_function_points": Variant(points)])
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name:"a",
                                   attributes: ["formula": "g1 + g2"])
        
        frame.createEdge(ObjectType.Parameter, origin: g1, target: aux)
        frame.createEdge(ObjectType.Parameter, origin: g2, target: aux)
        frame.createEdge(ObjectType.Parameter, origin: p1, target: g1)
        frame.createEdge(ObjectType.Parameter, origin: p2, target: g2)
        
        try compile()

        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        try sim.initialize(&state)

        XCTAssertEqual(state[g1], 0.0)
        XCTAssertEqual(state[g2], 10.0)
        XCTAssertEqual(state[aux], 10.0)
        
    }
    
    // Other tests - that should rather be at lower level
    
    func testIfBuiltinFunction() throws {
        // TODO: This should be tested at expression evaluation level
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "a",
                                   attributes: ["formula": "if(time < 2, 0, 1)"])

        try compile()

        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        try sim.initialize(&state)
        var context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)

        let index = model.variableIndex(of: aux)!
        
        XCTAssertEqual(state[index], 0.0)
        
        try sim.update(&state, context: context)
        XCTAssertEqual(state[index], 0.0)

        state[model.timeVariableIndex] = 2.0
        try sim.update(&state, context: context)
        XCTAssertEqual(state[index], 1.0)

        state[model.timeVariableIndex] = 3.0
        try sim.update(&state, context: context)
        XCTAssertEqual(state[index], 1.0)
    }

    func testDelay() throws {
        let delay = frame.createNode(ObjectType.Delay,
                                      name: "delay",
                                      attributes: [
                                        "delay_duration": "2",
                                        "initial_value": "0.0",
                                      ])
        let x = frame.createNode(ObjectType.Auxiliary,
                                    name: "x",
                                    attributes: ["formula": "10"])
        
        frame.createEdge(ObjectType.Parameter, origin: x, target: delay)
        
        try compile()

        let sim = StockFlowSimulation(model)
        var state = SimulationState(model: model)
        try sim.initialize(&state)
        var context = SimulationContext(step: 1, time: 1.0, timeDelta: 1.0)

        XCTAssertEqual(state[delay], 0.0)

        try sim.update(&state, context: context)
        XCTAssertEqual(state[delay], 0.0)

        try sim.update(&state, context: context)
        XCTAssertEqual(state[delay], 0.0)

        try sim.update(&state, context: context)
        XCTAssertEqual(state[delay], 10.0)
    }
}