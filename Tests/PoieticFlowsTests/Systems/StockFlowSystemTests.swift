//
//  StockFlowSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct FlowTopologySystemTests {
    let design: Design
    let frame: TransientPlane

    init() throws {
        self.design = Design(metamodel: StockFlowDomain.StockFlowMetamodel)
        self.frame = design.createPlane()
    }

    func accept(_ frame: TransientPlane) throws -> World {
        let stable = try design.accept(frame)
        return World(plane: stable)
    }

    // MARK: - Basic Sanity Tests

    @Test func isolatedFlowRate() throws {
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "isolated")

        let world = try accept(frame)
        try StockFlowTopologySystem.update(world)

        let component: FlowRate = try #require(world.entity(flowRate.objectID)?.component())
        #expect(component.drainsStock == nil)
        #expect(component.fillsStock == nil)
    }

    // MARK: - Single Connection Scenarios

    @Test func flowRateDrainingStock() throws {
        let stock = frame.createNode(StockFlowDomain.Types.Stock,name: "stock")
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "drain")
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stock, target: flowRate)

        let world = try accept(frame)
        try StockFlowTopologySystem.update(world)

        let component: FlowRate = try #require(world.entity(flowRate.objectID)?.component())
        #expect(component.drainsStock == stock.objectID)
        #expect(component.fillsStock == nil)
    }

    @Test func flowRateFillingStock() throws {
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "fill")
        let stock = frame.createNode(StockFlowDomain.Types.Stock, name: "stock")
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowRate, target: stock)

        let world = try accept(frame)
        try StockFlowTopologySystem.update(world)

        let component: FlowRate = try #require(world.entity(flowRate.objectID)?.component())
        #expect(component.drainsStock == nil)
        #expect(component.fillsStock == stock.objectID)
    }

    @Test func flowRateBetweenStocks() throws {
        let source = frame.createNode(StockFlowDomain.Types.Stock, name: "source")
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "transfer")
        let target = frame.createNode(StockFlowDomain.Types.Stock, name: "target")

        frame.createEdge(StockFlowDomain.Types.Flow, origin: source, target: flowRate)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowRate, target: target)

        let world = try accept(frame)
        try StockFlowTopologySystem.update(world)

        let component: FlowRate = try #require(world.entity(flowRate.objectID)?.component())
        #expect(component.drainsStock == source.objectID)
        #expect(component.fillsStock == target.objectID)
    }

    @Test func flowRateBetweenClouds() throws {
        let source = frame.createNode(StockFlowDomain.Types.Cloud, name: "source")
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "transfer")
        let target = frame.createNode(StockFlowDomain.Types.Cloud, name: "target")

        frame.createEdge(StockFlowDomain.Types.Flow, origin: source, target: flowRate)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowRate, target: target)

        let world = try accept(frame)
        try StockFlowTopologySystem.update(world)

        let component: FlowRate = try #require(world.entity(flowRate.objectID)?.component())
        #expect(component.drainsStock == source.objectID)
        #expect(component.fillsStock == target.objectID)
    }

    // MARK: - Priority Handling

    @Test func flowRateWithExplicitPriority() throws {
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "priority_flow", attributes: ["priority": 5])

        let world = try accept(frame)
        try StockFlowTopologySystem.update(world)

        let component: FlowRate = try #require(world.entity(flowRate.objectID)?.component())
    }
}

@Suite struct StockTopologySystemTests {
    let design: Design
    let frame: TransientPlane
    
    init() throws {
        self.design = Design(metamodel: StockFlowDomain.StockFlowMetamodel)
        self.frame = design.createPlane()
    }
    
    func accept(_ frame: TransientPlane) throws -> World {
        let stable = try design.accept(frame)
        let world = World(plane: stable)
        try StockFlowTopologySystem.update(world)
        return world
    }
    
    // MARK: - Basic Sanity Tests
    
    @Test func isolatedStock() throws {
        let stock = frame.createNode(StockFlowDomain.Types.Stock, name: "isolated")
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let component: Stock = try #require(world.entity(stock.objectID)?.component())
        #expect(component.inflowRates.isEmpty)
        #expect(component.outflowRates.isEmpty)
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
        #expect(component.allowsNegative == false)
    }
    
    // MARK: - Single Flow Scenarios
    
    @Test func stockWithOneInflow() throws {
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "inflow")
        let stock = frame.createNode(StockFlowDomain.Types.Stock, name: "stock")
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowRate, target: stock)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let component: Stock = try #require(world.entity(stock.objectID)?.component())
        #expect(component.inflowRates == [flowRate.objectID])
        #expect(component.outflowRates.isEmpty)
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
    }
    
    @Test func stockWithOneOutflow() throws {
        let stock = frame.createNode(StockFlowDomain.Types.Stock, name: "stock")
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "outflow")
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stock, target: flowRate)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let component: Stock = try #require(world.entity(stock.objectID)?.component())
        #expect(component.inflowRates.isEmpty)
        #expect(component.outflowRates == [flowRate.objectID])
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
    }
    
    @Test func stockWithInflowAndOutflow() throws {
        let inflow = frame.createNode(StockFlowDomain.Types.FlowRate, name: "inflow")
        let stock = frame.createNode(StockFlowDomain.Types.Stock, name: "stock")
        let outflow = frame.createNode(StockFlowDomain.Types.FlowRate, name: "outflow")
        
        frame.createEdge(StockFlowDomain.Types.Flow, origin: inflow, target: stock)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stock, target: outflow)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let component: Stock = try #require(world.entity(stock.objectID)?.component())
        #expect(component.inflowRates == [inflow.objectID])
        #expect(component.outflowRates == [outflow.objectID])
        #expect(component.inflowStocks.isEmpty)
        #expect(component.outflowStocks.isEmpty)
    }
    
    // MARK: - Multiple Flow Scenarios
    
    @Test func stockWithMultipleInflowsAndOutflows() throws {
        let inflow1 = frame.createNode(StockFlowDomain.Types.FlowRate, name: "inflow1")
        let inflow2 = frame.createNode(StockFlowDomain.Types.FlowRate, name: "inflow2")
        let stock = frame.createNode(StockFlowDomain.Types.Stock, name: "stock")
        let outflow1 = frame.createNode(StockFlowDomain.Types.FlowRate, name: "outflow1")
        let outflow2 = frame.createNode(StockFlowDomain.Types.FlowRate, name: "outflow2")
        
        frame.createEdge(StockFlowDomain.Types.Flow, origin: inflow1, target: stock)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: inflow2, target: stock)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stock, target: outflow1)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stock, target: outflow2)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let component: Stock = try #require(world.entity(stock.objectID)?.component())
        #expect(component.inflowRates.count == 2)
        #expect(component.inflowRates.contains(inflow1.objectID))
        #expect(component.inflowRates.contains(inflow2.objectID))
        #expect(component.outflowRates.count == 2)
        #expect(component.outflowRates.contains(outflow1.objectID))
        #expect(component.outflowRates.contains(outflow2.objectID))
    }
    
    // MARK: - Transitive Stock Relationships
    
    @Test func twoStocksConnectedByFlow() throws {
        let stockA = frame.createNode(StockFlowDomain.Types.Stock, name: "A")
        let flowRate = frame.createNode(StockFlowDomain.Types.FlowRate, name: "transfer")
        let stockB = frame.createNode(StockFlowDomain.Types.Stock, name: "B")
        
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stockA, target: flowRate)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowRate, target: stockB)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let compA: Stock = try #require(world.entity(stockA.objectID)?.component())
        #expect(compA.outflowRates == [flowRate.objectID])
        #expect(compA.outflowStocks == [stockB.objectID])
        #expect(compA.inflowStocks.isEmpty)
        
        let compB: Stock = try #require(world.entity(stockB.objectID)?.component())
        #expect(compB.inflowRates == [flowRate.objectID])
        #expect(compB.inflowStocks == [stockA.objectID])
        #expect(compB.outflowStocks.isEmpty)
    }
    
    @Test func chainOfThreeStocks() throws {
        // A → flowAB → B → flowBC → C
        let stockA = frame.createNode(StockFlowDomain.Types.Stock, name: "A")
        let flowAB = frame.createNode(StockFlowDomain.Types.FlowRate, name: "AB")
        let stockB = frame.createNode(StockFlowDomain.Types.Stock, name: "B")
        let flowBC = frame.createNode(StockFlowDomain.Types.FlowRate, name: "BC")
        let stockC = frame.createNode(StockFlowDomain.Types.Stock, name: "C")
        
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stockA, target: flowAB)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowAB, target: stockB)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stockB, target: flowBC)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: flowBC, target: stockC)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)
        
        let compA: Stock = try #require(world.entity(stockA.objectID)?.component())
        #expect(compA.inflowStocks.isEmpty)
        #expect(compA.outflowStocks == [stockB.objectID])
        
        let compB: Stock = try #require(world.entity(stockB.objectID)?.component())
        #expect(compB.inflowStocks == [stockA.objectID])
        #expect(compB.outflowStocks == [stockC.objectID])
        
        let compC: Stock = try #require(world.entity(stockC.objectID)?.component())
        #expect(compC.inflowStocks == [stockB.objectID])
        #expect(compC.outflowStocks.isEmpty)
    }
    
    @Test func stockCycle() throws {
        let stockA = frame.createNode(StockFlowDomain.Types.Stock, name: "A")
        let rateAB = frame.createNode(StockFlowDomain.Types.FlowRate, name: "AB")
        let stockB = frame.createNode(StockFlowDomain.Types.Stock, name: "B")
        let rateBA = frame.createNode(StockFlowDomain.Types.FlowRate, name: "BA")
        
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stockA, target: rateAB)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: rateAB, target: stockB)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: stockB, target: rateBA)
        frame.createEdge(StockFlowDomain.Types.Flow, origin: rateBA, target: stockA)
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let compA: Stock = try #require(world.entity(stockA.objectID)?.component())
        #expect(compA.outflowRates == [rateAB.objectID])
        #expect(compA.outflowStocks == [stockB.objectID])
        #expect(compA.inflowRates == [rateBA.objectID])
        #expect(compA.inflowStocks == [stockB.objectID])
        
        let compB: Stock = try #require(world.entity(stockB.objectID)?.component())
        #expect(compB.inflowRates == [rateAB.objectID])
        #expect(compB.inflowStocks == [stockA.objectID])
        #expect(compB.outflowRates == [rateBA.objectID])
        #expect(compB.outflowStocks == [stockA.objectID])
    }
    
    // MARK: - Attribute Handling
    
    @Test func stockWithAllowsNegativeTrue() throws {
        let stockNeg = frame.createNode(StockFlowDomain.Types.Stock, name: "stock1", attributes: ["allows_negative": true])
        let stockNotNeg = frame.createNode(StockFlowDomain.Types.Stock, name: "stock2", attributes: ["allows_negative": false])
        
        let world = try accept(frame)
        
        try StockFlowTopologySystem.update(world)

        let component1: Stock = try #require(world.entity(stockNeg.objectID)?.component())
        #expect(component1.allowsNegative == true)
        let component2: Stock = try #require(world.entity(stockNotNeg.objectID)?.component())
        #expect(component2.allowsNegative == false)
    }
}
