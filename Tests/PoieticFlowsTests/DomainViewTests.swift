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
        db = Design(metamodel: StockFlowMetamodel)
        trans = db.createFrame()
    }
        
    @Test func testInvalidInput2() throws {
        let broken = trans.createNode(.Stock, name: "broken", attributes: ["formula": "price"])
        let frame = try! db.validate(try! db.accept(trans))
        
        let view = StockFlowView(frame)
        
        let resolved = view.resolveParameters(broken.objectID, required:["price"])
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
        let resolved = view.resolveParameters(tested.objectID, required:["used"])
        
        #expect(resolved.missing.count == 0)
        #expect(resolved.unused.count == 1)
        #expect(resolved.unused.first?.object.objectID == unusedEdge.objectID)
    }
    
    @Test func testUnknownParameters() throws {
        let known = trans.createNode(ObjectType.Auxiliary, name: "known", attributes: ["formula": "0"])
        let tested = trans.createNode(ObjectType.Auxiliary, name: "tested", attributes: ["formula": "known + unknown"])
        let _ = trans.createEdge(ObjectType.Parameter, origin: known, target: tested)
        
        let frame = try! db.validate(try! db.accept(trans))
        let view = StockFlowView(frame)
        
        let resolved = view.resolveParameters(tested.objectID, required:["known", "unknown"])
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
        
        #expect(view.fills(flow.objectID) == sink.objectID)
        #expect(view.drains(flow.objectID) == source.objectID)
    }
}
