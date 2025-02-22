//
//  TestDomainView.swift
//
//
//  Created by Stefan Urbanek on 07/06/2023.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore


@Suite struct TestDomainView {
    // TODO: Split to Compiler and DomainView test cases
    
    let db: Design
    let frame: TransientFrame
    
    init() throws {
        db = Design(metamodel: FlowsMetamodel)
        frame = db.createFrame()
    }
        
    @Test func testInvalidInput2() throws {
        let broken = frame.createNode(.Stock, name: "broken", attributes: ["formula": "price"])
        let view = StockFlowView(frame)
        
        let resolved = view.resolveParameters(broken.id, required:["price"])
        #expect(resolved.missing.count == 1)
        #expect(resolved.unused.count == 0)
        #expect(resolved.missing == ["price"])
    }
    
    @Test func testUnusedInputs() throws {
        let used = frame.createNode(.Auxiliary, name: "used", attributes: ["formula": "0"])
        let unused = frame.createNode(.Auxiliary, name: "unused", attributes: ["formula": "0"])
        let tested = frame.createNode(.Auxiliary, name: "tested", attributes: ["formula": "used"])
        
        let _ = frame.createEdge(.Parameter, origin: used, target: tested)
        let unusedEdge = frame.createEdge(.Parameter, origin: unused, target: tested)
        
        let view = StockFlowView(frame)
        
        // TODO: Get the required list from the compiler
        let resolved = view.resolveParameters(tested.id, required:["used"])
        
        #expect(resolved.missing.count == 0)
        #expect(resolved.unused.count == 1)
        #expect(resolved.unused.first?.object.id == unusedEdge.id)
    }
    
    @Test func testUnknownParameters() throws {
        let known = frame.createNode(ObjectType.Auxiliary, name: "known", attributes: ["formula": "0"])
        let tested = frame.createNode(ObjectType.Auxiliary, name: "tested", attributes: ["formula": "known + unknown"])
        let _ = frame.createEdge(ObjectType.Parameter, origin: known, target: tested)
        
        let view = StockFlowView(frame)
        
        let resolved = view.resolveParameters(tested.id, required:["known", "unknown"])
        #expect(resolved.missing.count == 1)
        #expect(resolved.unused.count == 0)

        #expect(resolved.missing == ["unknown"])
    }
    
    @Test func testFlowFillsAndDrains() throws {
        let flow = frame.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "1"])
        let source = frame.createNode(ObjectType.Stock, name: "source", attributes: ["formula": "0"])
        let sink = frame.createNode(ObjectType.Stock, name: "sink", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: source, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: sink)
        
        let view = StockFlowView(frame)
        
        #expect(view.fills(flow.id) == sink.id)
        #expect(view.drains(flow.id) == source.id)
    }
   
    @Test func testStockAdjacency() throws {
        // TODO: Test loops and delayed inflow
        let a = frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        let b = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        let c = frame.createNode(ObjectType.Stock, name: "c", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "0"])
        let inflow = frame.createNode(ObjectType.FlowRate, name: "inflow", attributes: ["formula": "0"])
        let outflow = frame.createNode(ObjectType.FlowRate, name: "outflow", attributes: ["formula": "0"])

        frame.createEdge(ObjectType.Flow, origin: a, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: b)
        frame.createEdge(ObjectType.Flow, origin: inflow, target: c)
        frame.createEdge(ObjectType.Flow, origin: c, target: outflow)

        let view = StockFlowView(frame)

        let result = view.stockAdjacencies()
        #expect(result.count == 1)

        #expect(result[0].id == flow.id)
        #expect(result[0].origin == a.id)
        #expect(result[0].target == b.id)
    }
}
