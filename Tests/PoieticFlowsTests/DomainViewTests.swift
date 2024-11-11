//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 07/06/2023.
//

import XCTest
@testable import PoieticFlows
@testable import PoieticCore


final class TestDomainView: XCTestCase {
    // TODO: Split to Compiler and DomainView test cases
    
    var db: Design!
    var frame: TransientFrame!
    
    override func setUp() {
        db = Design(metamodel: FlowsMetamodel)
        frame = db.createFrame()
    }
    
    
    func testCompileExpressions() throws {
        throw XCTSkip("Conflicts with input validation, this test requires attention.")
#if false
        let names: [String:ObjectID] = [
            "a": 1,
            "b": 2,
        ]
        
        let l = frame.createNode(FlowsObjectType.Stock,
                                 traits: [FormulaComponent(name: "l",
                                                           expression: "sqrt(a*a + b*b)")])
        let view = StockFlowView(frame)
        
        let exprs = try view.boundExpressions(names: names)
        
        let varRefs = Set(exprs[l]!.allVariables)
        
        XCTAssertTrue(varRefs.contains(.object(1)))
        XCTAssertTrue(varRefs.contains(.object(2)))
        XCTAssertEqual(varRefs.count, 2)
#endif
    }
    
    func testSortedNodes() throws {
        // a -> b -> c
        
        let c = frame.createNode(ObjectType.Auxiliary, name: "c", attributes: ["formula": "b"])
        let b = frame.createNode(ObjectType.Auxiliary, name: "b", attributes: ["formula": "a"])
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "0"])
        
        
        frame.createEdge(ObjectType.Parameter, origin: a, target: b, components: [])
        frame.createEdge(ObjectType.Parameter, origin: b, target: c, components: [])
        
        let view = StockFlowView(frame)
        let sortedNodes = try view.sortedNodesByParameter([b.id, c.id, a.id])
        
        if sortedNodes.isEmpty {
            XCTFail("Sorted expression nodes must not be empty")
            return
        }
        
        XCTAssertEqual(sortedNodes.count, 3)
        XCTAssertEqual(sortedNodes[0].id, a.id)
        XCTAssertEqual(sortedNodes[1].id, b.id)
        XCTAssertEqual(sortedNodes[2].id, c.id)
    }
    
    func testInvalidInput2() throws {
        let broken = frame.createNode(ObjectType.Stock, name: "broken", attributes: ["formula": "price"])
        let view = StockFlowView(frame)
        
        let parameters = view.parameters(broken.id, required:["price"])
        XCTAssertEqual(parameters.count, 1)
        XCTAssertEqual(parameters["price"], ParameterStatus.missing)
    }
    
    func testUnusedInputs() throws {
        let used = frame.createNode(ObjectType.Auxiliary, name: "used", attributes: ["formula": "0"])
        let unused = frame.createNode(ObjectType.Auxiliary, name: "unused", attributes: ["formula": "0"])
        let tested = frame.createNode(ObjectType.Auxiliary, name: "tested", attributes: ["formula": "used"])
        
        let usedEdge = frame.createEdge(ObjectType.Parameter, origin: used, target: tested, components: [])
        let unusedEdge = frame.createEdge(ObjectType.Parameter, origin: unused, target: tested, components: [])
        
        let view = StockFlowView(frame)
        
        // TODO: Get the required list from the compiler
        let parameters = view.parameters(tested.id, required:["used"])
        
        XCTAssertEqual(parameters.count, 2)
        XCTAssertEqual(parameters["unused"], ParameterStatus.unused(node: unused.id, edge: unusedEdge.id))
        XCTAssertEqual(parameters["used"], ParameterStatus.used(node: used.id, edge: usedEdge.id))
    }
    
    func testUnknownParameters() throws {
        let known = frame.createNode(ObjectType.Auxiliary, name: "known", attributes: ["formula": "0"])
        let tested = frame.createNode(ObjectType.Auxiliary, name: "tested", attributes: ["formula": "known + unknown"])
        
        let knownEdge = frame.createEdge(ObjectType.Parameter, origin: known, target: tested, components: [])
        
        let view = StockFlowView(frame)
        
        let parameters = view.parameters(tested.id, required:["known", "unknown"])
        XCTAssertEqual(parameters.count, 2)
        XCTAssertEqual(parameters["known"], ParameterStatus.used(node: known.id, edge: knownEdge.id))
        XCTAssertEqual(parameters["unknown"], ParameterStatus.missing)
    }
    
    func testFlowFillsAndDrains() throws {
        let flow = frame.createNode(ObjectType.Flow, name: "f", attributes: ["formula": "1"])
        let source = frame.createNode(ObjectType.Stock, name: "source", attributes: ["formula": "0"])
        let sink = frame.createNode(ObjectType.Stock, name: "sink", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Drains, origin: source, target: flow, components: [])
        frame.createEdge(ObjectType.Fills, origin: flow, target: sink, components: [])
        
        let view = StockFlowView(frame)
        
        XCTAssertEqual(view.flowFills(flow.id), sink.id)
        XCTAssertEqual(view.flowDrains(flow.id), source.id)
    }
   
    func testStockAdjacency() throws {
        // TODO: Test loops and delayed inflow
        let a = frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        let b = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        let c = frame.createNode(ObjectType.Stock, name: "c", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.Flow, name: "f", attributes: ["formula": "0"])
        let inflow = frame.createNode(ObjectType.Flow, name: "inflow", attributes: ["formula": "0"])
        let outflow = frame.createNode(ObjectType.Flow, name: "outflow", attributes: ["formula": "0"])

        frame.createEdge(ObjectType.Drains, origin: a, target: flow, components: [])
        frame.createEdge(ObjectType.Fills, origin: flow, target: b, components: [])
        frame.createEdge(ObjectType.Fills, origin: inflow, target: c, components: [])
        frame.createEdge(ObjectType.Drains, origin: c, target: outflow, components: [])

        let view = StockFlowView(frame)

        let result = view.stockAdjacencies()
        XCTAssertEqual(result.count, 1)

        XCTAssertEqual(result[0].id, flow.id)
        XCTAssertEqual(result[0].origin, a.id)
        XCTAssertEqual(result[0].target, b.id)
    }
}
