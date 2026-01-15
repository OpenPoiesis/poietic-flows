//
//  StockFlowSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct FlowCollectorSystemTests {
    let design: Design
    let frame: TransientFrame

    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }

    func accept(_ frame: TransientFrame) throws -> World {
        let stable = try design.accept(frame)
        return World(frame: stable)
    }

    // MARK: - Basic Sanity Tests

    @Test func isolatedFlowRate() throws {
        let flowRate = frame.createNode(.FlowRate, name: "isolated")

        let world = try accept(frame)
        let system = FlowCollectorSystem(world)
        try system.update(world)

        let component: FlowRateComponent = try #require(world.component(for: flowRate.objectID))
        #expect(component.drainsStock == nil)
        #expect(component.fillsStock == nil)
        #expect(component.priority == 0)
    }

    // MARK: - Single Connection Scenarios

    @Test func flowRateDrainingStock() throws {
        let stock = frame.createNode(.Stock, name: "stock")
        let flowRate = frame.createNode(.FlowRate, name: "drain")
        frame.createEdge(.Flow, origin: stock, target: flowRate)

        let world = try accept(frame)
        let system = FlowCollectorSystem(world)
        try system.update(world)

        let component: FlowRateComponent = try #require(world.component(for: flowRate.objectID))
        #expect(component.drainsStock == stock.objectID)
        #expect(component.fillsStock == nil)
        #expect(component.priority == 0)
    }

    @Test func flowRateFillingStock() throws {
        let flowRate = frame.createNode(.FlowRate, name: "fill")
        let stock = frame.createNode(.Stock, name: "stock")
        frame.createEdge(.Flow, origin: flowRate, target: stock)

        let world = try accept(frame)
        let system = FlowCollectorSystem(world)
        try system.update(world)

        let component: FlowRateComponent = try #require(world.component(for: flowRate.objectID))
        #expect(component.drainsStock == nil)
        #expect(component.fillsStock == stock.objectID)
        #expect(component.priority == 0)
    }

    @Test func flowRateBetweenStocks() throws {
        let source = frame.createNode(.Stock, name: "source")
        let flowRate = frame.createNode(.FlowRate, name: "transfer")
        let target = frame.createNode(.Stock, name: "target")

        frame.createEdge(.Flow, origin: source, target: flowRate)
        frame.createEdge(.Flow, origin: flowRate, target: target)

        let world = try accept(frame)
        let system = FlowCollectorSystem(world)
        try system.update(world)

        let component: FlowRateComponent = try #require(world.component(for: flowRate.objectID))
        #expect(component.drainsStock == source.objectID)
        #expect(component.fillsStock == target.objectID)
        #expect(component.priority == 0)
    }

    @Test func flowRateBetweenClouds() throws {
        let source = frame.createNode(.Cloud, name: "source")
        let flowRate = frame.createNode(.FlowRate, name: "transfer")
        let target = frame.createNode(.Cloud, name: "target")

        frame.createEdge(.Flow, origin: source, target: flowRate)
        frame.createEdge(.Flow, origin: flowRate, target: target)

        let world = try accept(frame)
        let system = FlowCollectorSystem(world)
        try system.update(world)

        let component: FlowRateComponent = try #require(world.component(for: flowRate.objectID))
        #expect(component.drainsStock == source.objectID)
        #expect(component.fillsStock == target.objectID)
        #expect(component.priority == 0)
    }

    // MARK: - Priority Handling

    @Test func flowRateWithExplicitPriority() throws {
        let flowRate = frame.createNode(.FlowRate, name: "priority_flow", attributes: ["priority": 5])

        let world = try accept(frame)
        let system = FlowCollectorSystem(world)
        try system.update(world)

        let component: FlowRateComponent = try #require(world.component(for: flowRate.objectID))
        #expect(component.priority == 5)
    }
}

@Suite struct StockDependencySystemTests {
    let design: Design
    let frame: TransientFrame
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }
    
    func accept(_ frame: TransientFrame) throws -> World {
        let stable = try design.accept(frame)
        let world = World(frame: stable)
        let flowSystem = FlowCollectorSystem(world)
        try flowSystem.update(world)
        return world
    }
    
    // MARK: - Basic Sanity Tests
    
    @Test func isolatedStock() throws {
        let stock = frame.createNode(.Stock, name: "isolated")
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let component: StockComponent = try #require(world.component(for: stock.objectID))
        #expect(component.inflowRates.isEmpty)
        #expect(component.outflowRates.isEmpty)
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
        #expect(component.allowsNegative == false)
    }
    
    // MARK: - Single Flow Scenarios
    
    @Test func stockWithOneInflow() throws {
        let flowRate = frame.createNode(.FlowRate, name: "inflow")
        let stock = frame.createNode(.Stock, name: "stock")
        frame.createEdge(.Flow, origin: flowRate, target: stock)
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let component: StockComponent = try #require(world.component(for: stock.objectID))
        #expect(component.inflowRates == [flowRate.objectID])
        #expect(component.outflowRates.isEmpty)
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
    }
    
    @Test func stockWithOneOutflow() throws {
        let stock = frame.createNode(.Stock, name: "stock")
        let flowRate = frame.createNode(.FlowRate, name: "outflow")
        frame.createEdge(.Flow, origin: stock, target: flowRate)
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let component: StockComponent = try #require(world.component(for: stock.objectID))
        #expect(component.inflowRates.isEmpty)
        #expect(component.outflowRates == [flowRate.objectID])
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
    }
    
    @Test func stockWithInflowAndOutflow() throws {
        let inflow = frame.createNode(.FlowRate, name: "inflow")
        let stock = frame.createNode(.Stock, name: "stock")
        let outflow = frame.createNode(.FlowRate, name: "outflow")
        
        frame.createEdge(.Flow, origin: inflow, target: stock)
        frame.createEdge(.Flow, origin: stock, target: outflow)
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let component: StockComponent = try #require(world.component(for: stock.objectID))
        #expect(component.inflowRates == [inflow.objectID])
        #expect(component.outflowRates == [outflow.objectID])
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
    }
    
    // MARK: - Multiple Flow Scenarios
    
    @Test func stockWithMultipleInflowsAndOutflows() throws {
        let inflow1 = frame.createNode(.FlowRate, name: "inflow1")
        let inflow2 = frame.createNode(.FlowRate, name: "inflow2")
        let stock = frame.createNode(.Stock, name: "stock")
        let outflow1 = frame.createNode(.FlowRate, name: "outflow1")
        let outflow2 = frame.createNode(.FlowRate, name: "outflow2")
        
        frame.createEdge(.Flow, origin: inflow1, target: stock)
        frame.createEdge(.Flow, origin: inflow2, target: stock)
        frame.createEdge(.Flow, origin: stock, target: outflow1)
        frame.createEdge(.Flow, origin: stock, target: outflow2)
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let component: StockComponent = try #require(world.component(for: stock.objectID))
        #expect(component.inflowRates.count == 2)
        #expect(component.inflowRates.contains(inflow1.objectID))
        #expect(component.inflowRates.contains(inflow2.objectID))
        #expect(component.outflowRates.count == 2)
        #expect(component.outflowRates.contains(outflow1.objectID))
        #expect(component.outflowRates.contains(outflow2.objectID))
    }
    
    // MARK: - Transitive Stock Relationships
    
    @Test func twoStocksConnectedByFlow() throws {
        let stockA = frame.createNode(.Stock, name: "A")
        let flowRate = frame.createNode(.FlowRate, name: "transfer")
        let stockB = frame.createNode(.Stock, name: "B")
        
        frame.createEdge(.Flow, origin: stockA, target: flowRate)
        frame.createEdge(.Flow, origin: flowRate, target: stockB)
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let compA: StockComponent = try #require(world.component(for: stockA.objectID))
        #expect(compA.outflowRates == [flowRate.objectID])
        #expect(compA.outflowStocks == [stockB.objectID])
        #expect(compA.inflowStocks.isEmpty)
        
        let compB: StockComponent = try #require(world.component(for: stockB.objectID))
        #expect(compB.inflowRates == [flowRate.objectID])
        #expect(compB.inflowStocks == [stockA.objectID])
        #expect(compB.outflowStocks.isEmpty)
    }
    
    @Test func chainOfThreeStocks() throws {
        // A → flowAB → B → flowBC → C
        let stockA = frame.createNode(.Stock, name: "A")
        let flowAB = frame.createNode(.FlowRate, name: "AB")
        let stockB = frame.createNode(.Stock, name: "B")
        let flowBC = frame.createNode(.FlowRate, name: "BC")
        let stockC = frame.createNode(.Stock, name: "C")
        
        frame.createEdge(.Flow, origin: stockA, target: flowAB)
        frame.createEdge(.Flow, origin: flowAB, target: stockB)
        frame.createEdge(.Flow, origin: stockB, target: flowBC)
        frame.createEdge(.Flow, origin: flowBC, target: stockC)
        
        let world = try accept(frame)
        
        let flowSystem = FlowCollectorSystem(world)
        try flowSystem.update(world)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let compA: StockComponent = try #require(world.component(for: stockA.objectID))
        #expect(compA.inflowStocks.isEmpty)
        #expect(compA.outflowStocks == [stockB.objectID])
        
        let compB: StockComponent = try #require(world.component(for: stockB.objectID))
        #expect(compB.inflowStocks == [stockA.objectID])
        #expect(compB.outflowStocks == [stockC.objectID])
        
        let compC: StockComponent = try #require(world.component(for: stockC.objectID))
        #expect(compC.inflowStocks == [stockB.objectID])
        #expect(compC.outflowStocks.isEmpty)
    }
    
    @Test func stockCycle() throws {
        let stockA = frame.createNode(.Stock, name: "A")
        let rateAB = frame.createNode(.FlowRate, name: "AB")
        let stockB = frame.createNode(.Stock, name: "B")
        let rateBA = frame.createNode(.FlowRate, name: "BA")
        
        frame.createEdge(.Flow, origin: stockA, target: rateAB)
        frame.createEdge(.Flow, origin: rateAB, target: stockB)
        frame.createEdge(.Flow, origin: stockB, target: rateBA)
        frame.createEdge(.Flow, origin: rateBA, target: stockA)
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let compA: StockComponent = try #require(world.component(for: stockA.objectID))
        #expect(compA.outflowRates == [rateAB.objectID])
        #expect(compA.outflowStocks == [stockB.objectID])
        #expect(compA.inflowRates == [rateBA.objectID])
        #expect(compA.inflowStocks == [stockB.objectID])
        
        let compB: StockComponent = try #require(world.component(for: stockB.objectID))
        #expect(compB.inflowRates == [rateAB.objectID])
        #expect(compB.inflowStocks == [stockA.objectID])
        #expect(compB.outflowRates == [rateBA.objectID])
        #expect(compB.outflowStocks == [stockA.objectID])
    }
    
    // MARK: - Attribute Handling
    
    @Test func stockWithAllowsNegativeTrue() throws {
        let stockNeg = frame.createNode(.Stock, name: "stock1", attributes: ["allows_negative": true])
        let stockNotNeg = frame.createNode(.Stock, name: "stock2", attributes: ["allows_negative": false])
        
        let world = try accept(frame)
        
        let system = StockDependencySystem(world)
        try system.update(world)
        
        let component1: StockComponent = try #require(world.component(for: stockNeg.objectID))
        #expect(component1.allowsNegative == true)
        let component2: StockComponent = try #require(world.component(for: stockNotNeg.objectID))
        #expect(component2.allowsNegative == false)
    }
}
