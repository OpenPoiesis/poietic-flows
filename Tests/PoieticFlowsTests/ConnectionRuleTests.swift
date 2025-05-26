//
//  Test.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 20/02/2025.
//

import Testing
@testable import PoieticCore

@Suite struct ConnectionRuleTest {
    let metamodel: Metamodel
    let design: Design
    let checker: ConstraintChecker
    
    init() throws {
        self.metamodel = Metamodel.StockFlowBase
        self.design = Design(metamodel: self.metamodel)
        self.checker = ConstraintChecker(metamodel)
    }
    
    @Test func validParameterEdges() async throws {
        let frame = design.createFrame()
        let stock = frame.createNode(.Stock)
        let aux = frame.createNode(.Auxiliary)
        let flow = frame.createNode(.FlowRate)
        
        let aux_aux = frame.createEdge(.Parameter, origin: aux.objectID, target: aux.objectID)
        try checker.validate(edge: frame.edge(aux_aux.objectID)!, in: frame)
        
        let stock_aux = frame.createEdge(.Parameter, origin: stock.objectID, target: aux.objectID)
        try checker.validate(edge: frame.edge(stock_aux.objectID)!, in: frame)
        
        let flow_aux = frame.createEdge(.Parameter, origin: flow.objectID, target: aux.objectID)
        try checker.validate(edge: frame.edge(flow_aux.objectID)!, in: frame)
        
        let aux_flow = frame.createEdge(.Parameter, origin: aux.objectID, target: flow.objectID)
        try checker.validate(edge: frame.edge(aux_flow.objectID)!, in: frame)
        
        let stock_flow = frame.createEdge(.Parameter, origin: stock.objectID, target: flow.objectID)
        try checker.validate(edge: frame.edge(stock_flow.objectID)!, in: frame)
        
        let flow_flow = frame.createEdge(.Parameter, origin: flow.objectID, target: flow.objectID)
        try checker.validate(edge: frame.edge(flow_flow.objectID)!, in: frame)
    }
    
//    @Test func invalidParameterEdges() async throws {
//        let frame = design.createFrame()
//        let stock = frame.createNode(.Stock)
//        let aux = frame.createNode(.Auxiliary)
//        let flow = frame.createNode(.FlowRate)
//        
//        let aux_stock = frame.createEdge(.Parameter, origin: aux.id, target: stock.id)
//        #expect(throws: EdgeRuleViolation.noSatisfiedRule(.Parameter)) {
//            try checker.validate(edge: frame.edge(aux_stock.id), in: frame)
//        }
//        
//        
//        let stock_stock = frame.createEdge(.Parameter, origin: stock.id, target: stock.id)
//        #expect(throws: EdgeRuleViolation.noSatisfiedRule(.Parameter)) {
//            try checker.validate(edge: frame.edge(stock_stock.id), in: frame)
//        }
//        
//        let flow_stock = frame.createEdge(.Parameter, origin: flow.id, target: stock.id)
//        #expect(throws: EdgeRuleViolation.noSatisfiedRule(.Parameter)) {
//            try checker.validate(edge: frame.edge(flow_stock.id), in: frame)
//        }
//    }
    
    @Test func graphicalFunctionOneParameter() async throws {
        let frame = design.createFrame()
        let gf = frame.createNode(.GraphicalFunction)
        let aux = frame.createNode(.Auxiliary)

        let param1 = frame.createEdge(.Parameter, origin: aux, target: gf)
        try checker.validate(edge: frame.edge(param1.objectID)!, in: frame)

        let param2 = frame.createEdge(.Parameter, origin: aux, target: gf)
        #expect {
            try checker.validate(edge: frame.edge(param2.objectID)!, in: frame)
        }
        throws: {
            guard let error = $0 as? EdgeRuleViolation else {
                return false
            }
            guard case let .cardinalityViolation(rule, dir) = error else {
                return false
            }
            return rule.type === ObjectType.Parameter && dir == .incoming
        }
    }
}
