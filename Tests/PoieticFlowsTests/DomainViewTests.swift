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
    let trans: TransientFrame
    
    init() throws {
        db = Design(metamodel: FlowsMetamodel)
        trans = db.createFrame()
    }
        
    @Test func testInvalidInput2() throws {
        let broken = trans.createNode(.Stock, name: "broken", attributes: ["formula": "price"])
        let frame = try! db.validate(try! db.accept(trans))
        
        let view = StockFlowView(frame)
        
        let resolved = view.resolveParameters(broken.id, required:["price"])
        #expect(resolved.missing.count == 1)
        #expect(resolved.unused.count == 0)
        #expect(resolved.missing == ["price"])
    }
    
    @Test func testUnusedInputs() throws {
        let used = trans.createNode(.Auxiliary, name: "used", attributes: ["formula": "0"])
        let unused = trans.createNode(.Auxiliary, name: "unused", attributes: ["formula": "0"])
        let tested = trans.createNode(.Auxiliary, name: "tested", attributes: ["formula": "used"])
        
        let _ = trans.createEdge(.Parameter, origin: used, target: tested)
        let unusedEdge = trans.createEdge(.Parameter, origin: unused, target: tested)
        let frame = try! db.validate(try! db.accept(trans))
        let view = StockFlowView(frame)
        
        // TODO: Get the required list from the compiler
        let resolved = view.resolveParameters(tested.id, required:["used"])
        
        #expect(resolved.missing.count == 0)
        #expect(resolved.unused.count == 1)
        #expect(resolved.unused.first?.object.id == unusedEdge.id)
    }
    
    @Test func testUnknownParameters() throws {
        let known = trans.createNode(ObjectType.Auxiliary, name: "known", attributes: ["formula": "0"])
        let tested = trans.createNode(ObjectType.Auxiliary, name: "tested", attributes: ["formula": "known + unknown"])
        let _ = trans.createEdge(ObjectType.Parameter, origin: known, target: tested)
        
        let frame = try! db.validate(try! db.accept(trans))
        let view = StockFlowView(frame)
        
        let resolved = view.resolveParameters(tested.id, required:["known", "unknown"])
        #expect(resolved.missing.count == 1)
        #expect(resolved.unused.count == 0)

        #expect(resolved.missing == ["unknown"])
    }
    
    @Test func testFlowFillsAndDrains() throws {
        let flow = trans.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "1"])
        let source = trans.createNode(ObjectType.Stock, name: "source", attributes: ["formula": "0"])
        let sink = trans.createNode(ObjectType.Stock, name: "sink", attributes: ["formula": "0"])
        
        trans.createEdge(ObjectType.Flow, origin: source, target: flow)
        trans.createEdge(ObjectType.Flow, origin: flow, target: sink)
        
        let frame = try! db.validate(try! db.accept(trans))
        let view = StockFlowView(frame)
        
        #expect(view.fills(flow.id) == sink.id)
        #expect(view.drains(flow.id) == source.id)
    }
   
    @Test func testStockAdjacency() throws {
        // TODO: Test loops and delayed inflow
        let a = trans.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        let b = trans.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        let c = trans.createNode(ObjectType.Stock, name: "c", attributes: ["formula": "0"])
        let flow = trans.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "0"])
        let inflow = trans.createNode(ObjectType.FlowRate, name: "inflow", attributes: ["formula": "0"])
        let outflow = trans.createNode(ObjectType.FlowRate, name: "outflow", attributes: ["formula": "0"])

        trans.createEdge(ObjectType.Flow, origin: a, target: flow)
        trans.createEdge(ObjectType.Flow, origin: flow, target: b)
        trans.createEdge(ObjectType.Flow, origin: inflow, target: c)
        trans.createEdge(ObjectType.Flow, origin: c, target: outflow)

        let frame = try! db.validate(try! db.accept(trans))
        let view = StockFlowView(frame)

        let result = view.stockAdjacencies()
        #expect(result.count == 1)

        #expect(result[0].id == flow.id)
        #expect(result[0].origin == a.id)
        #expect(result[0].target == b.id)
    }
}
