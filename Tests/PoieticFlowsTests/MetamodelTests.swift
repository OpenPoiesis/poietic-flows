//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 09/07/2023.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore


@Suite struct FlowsMetamodelTest {
    let design: Design
    let frame: TransientFrame
    let checker: ConstraintChecker

    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
        self.checker = ConstraintChecker(design.metamodel)
    }
    

    @Test func testUniqueNames() throws {
        for type in StockFlowMetamodel.types {
            var attributes: [String:[String]] = [:]

            for trait in type.traits {
                for attribute in trait.attributes {
                    attributes[attribute.name, default: []].append(trait.name)
                }
            }
            for (_, traits) in attributes {
                #expect(traits.count <= 1)
            }
        }
    }
    
    @Test func metamodelTypeTraits() throws {
        let metamodel = StockFlowMetamodel
        for type in metamodel.types {
            for trait in type.traits {
                #expect(metamodel.trait(name: trait.name) != nil, "Missing trait \(trait.name)")
            }
        }
    }
    
    @Test func constraintStockFlowRate() throws {
        let a = frame.createNode(.Stock, name: "a", attributes: ["formula": "0"])
        let flow = frame.createNode(.FlowRate, name: "f", attributes: ["formula": "0"])
        let b = frame.createNode(.Stock, name: "b", attributes: ["formula": "0"])
        frame.createEdge(.Flow, origin: a, target: flow)
        frame.createEdge(.Flow, origin: flow, target: b)
        try checker.validate(frame)
    }
    @Test func constraintStockFlowRateFlowFlow() throws {
        let a = frame.createNode(.Stock, name: "a", attributes: ["formula": "0"])
        let flow = frame.createNode(.FlowRate, name: "f", attributes: ["formula": "0"])
        let b = frame.createNode(.Stock, name: "b", attributes: ["formula": "0"])
        let e1 = frame.createEdge(.Flow, origin: a, target: b)
        let e2 = frame.createEdge(.Flow, origin: flow, target: flow)
        // frame.createEdge(.Flow, origin: flow, target: b)
        let result = checker.diagnose(frame)
        #expect(result.edgeRuleViolations.count == 2)
        let err1 = try #require(result.edgeRuleViolations[e1.objectID]?.first)
        let err2 = try #require(result.edgeRuleViolations[e2.objectID]?.first)
        // NOTE: error cases are not comparable here
        switch (err1, err2) {
        case (.noRuleSatisfied, .noRuleSatisfied): #expect(true)
        default: #expect(false)
        }
    }
}
