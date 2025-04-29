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
        try checker.check(frame)
    }
    @Test func constraintStockFlowRateFlowFlow() throws {
        let a = frame.createNode(.Stock, name: "a", attributes: ["formula": "0"])
        let flow = frame.createNode(.FlowRate, name: "f", attributes: ["formula": "0"])
        let b = frame.createNode(.Stock, name: "b", attributes: ["formula": "0"])
        let e1 = frame.createEdge(.Flow, origin: a, target: b)
        let e2 = frame.createEdge(.Flow, origin: flow, target: flow)
        // frame.createEdge(.Flow, origin: flow, target: b)
        #expect {
            try checker.check(frame)
        } throws: {
            guard let error = $0 as? FrameValidationError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            guard error.edgeRuleViolations.count == 2 else {
                return false
            }
            guard let e1 = error.edgeRuleViolations[e1.id]?.first else {
                return false
            }
            guard let e2 = error.edgeRuleViolations[e2.id]?.first else {
                return false
            }
            switch (e1, e2) {
            case (.noRuleSatisfied, .noRuleSatisfied): return true
            default: return false
            }
        }
    }
}
