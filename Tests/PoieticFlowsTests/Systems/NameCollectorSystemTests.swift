//
//  NameCollectorSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct NameCollectorSystemTests {
    let design: Design
    let frame: TransientFrame
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }
    
    func accept(_ frame: TransientFrame) throws -> RuntimeFrame {
        let stable = try design.accept(frame)
        let validated = try design.validate(stable)
        let runtime = RuntimeFrame(validated)
        
        let system = SimulationOrderDependencySystem()
        try system.update(runtime)
        return runtime
    }
    
    @Test func empty() throws {
        let object = frame.createNode(.Note, name: "note")
        
        let runtime = try accept(frame)
        let system = NameCollectorSystem()
        try system.update(runtime)
        
        let lookup = try #require(runtime.frameComponent(SimulationNameLookupComponent.self))
        #expect(lookup.namedObjects.isEmpty)
        
        let component: SimObjectNameComponent? = runtime.component(for: object.objectID)
        #expect(component == nil)
    }
    
    @Test func emptyNames() throws {
        let empty = frame.createNode(.Auxiliary, name: "")
        let whitespace = frame.createNode(.Auxiliary, name: "  ")
        
        let runtime = try accept(frame)
        let system = NameCollectorSystem()
        try system.update(runtime)
        
        let lookup = try #require(runtime.frameComponent(SimulationNameLookupComponent.self))
        #expect(lookup.namedObjects.isEmpty)
        
        let component1: SimObjectNameComponent? = runtime.component(for: empty.objectID)
        #expect(component1 == nil)
        let component2: SimObjectNameComponent? = runtime.component(for: whitespace.objectID)
        #expect(component2 == nil)
    }
    
    @Test func trimmedName() throws {
        let object = frame.createNode(.Auxiliary, name: "  object \n")

        let runtime = try accept(frame)
        let system = NameCollectorSystem()
        try system.update(runtime)
        
        let lookup = try #require(runtime.frameComponent(SimulationNameLookupComponent.self))
        #expect(lookup.namedObjects["object"] == object.objectID)

        let component: SimObjectNameComponent = try #require(runtime.component(for: object.objectID))
        #expect(component.name == "object")
    }
    @Test func duplicateName() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")

        let runtime = try accept(frame)
        let system = NameCollectorSystem()
        try system.update(runtime)
        
        let component: SimObjectNameComponent? = runtime.component(for: object.objectID)
        #expect(component == nil)
        let dupeComponent: SimObjectNameComponent? = runtime.component(for: dupe.objectID)
        #expect(dupeComponent == nil)

        #expect(runtime.objectHasError(object.objectID, error: PlanningError.duplicateName("object")))
        #expect(runtime.objectHasError(dupe.objectID, error: PlanningError.duplicateName("object")))
    }
    @Test func validAndDuplicateMix() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")
        let single = frame.createNode(.Auxiliary, name: "single")

        let runtime = try accept(frame)
        let system = NameCollectorSystem()
        try system.update(runtime)
        
        let component: SimObjectNameComponent? = runtime.component(for: object.objectID)
        #expect(component == nil)
        let dupeComponent: SimObjectNameComponent? = runtime.component(for: dupe.objectID)
        #expect(dupeComponent == nil)
        let singleComponent: SimObjectNameComponent? = runtime.component(for: single.objectID)
        #expect(singleComponent?.name == "single")

        #expect(runtime.objectHasError(object.objectID, error: PlanningError.duplicateName("object")))
        #expect(runtime.objectHasError(dupe.objectID, error: PlanningError.duplicateName("object")))
        #expect(!runtime.objectHasIssues(single.objectID))
    }
}
