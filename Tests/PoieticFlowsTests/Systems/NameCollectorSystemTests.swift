//
//  NameCollectorSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct NameResolutionSystemTests {
    let design: Design
    let frame: TransientFrame
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }
    
    func accept(_ frame: TransientFrame) throws -> World {
        let accepted = try design.accept(frame)
        let world = World(frame: accepted)
        
        let system = ComputationOrderSystem(world)
        try system.update(world)
        return world
    }
    
    @Test func empty() throws {
        let object = frame.createNode(.Note, name: "note")
        
        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let lookup: SimulationNameLookupComponent = try #require(world.singleton())
        #expect(lookup.namedObjects.isEmpty)
        
        let component: SimulationObjectNameComponent? = world.component(for: object.objectID)
        #expect(component == nil)
    }
    
    @Test func emptyNames() throws {
        let empty = frame.createNode(.Auxiliary, name: "")
        let whitespace = frame.createNode(.Auxiliary, name: " \t\n\r")
        
        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let lookup: SimulationNameLookupComponent = try #require(world.singleton())
        #expect(lookup.namedObjects.isEmpty)
        
        #expect(world.objectHasError(empty.objectID, error: ModelError.emptyName))
        #expect(world.objectHasError(whitespace.objectID, error: ModelError.emptyName))
        
        let component1: SimulationObjectNameComponent? = world.component(for: empty.objectID)
        #expect(component1 == nil)
        let component2: SimulationObjectNameComponent? = world.component(for: whitespace.objectID)
        #expect(component2 == nil)
    }
    
    @Test func trimmedName() throws {
        let object = frame.createNode(.Auxiliary, name: "  object \n")

        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let lookup: SimulationNameLookupComponent = try #require(world.singleton())
        #expect(lookup.namedObjects["object"] == object.objectID)

        let component: SimulationObjectNameComponent = try #require(world.component(for: object.objectID))
        #expect(component.name == "object")
    }
    @Test func duplicateName() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")

        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let component: SimulationObjectNameComponent? = world.component(for: object.objectID)
        #expect(component == nil)
        let dupeComponent: SimulationObjectNameComponent? = world.component(for: dupe.objectID)
        #expect(dupeComponent == nil)

        #expect(world.objectHasError(object.objectID, error: ModelError.duplicateName("object")))
        #expect(world.objectHasError(dupe.objectID, error: ModelError.duplicateName("object")))
    }
    @Test func validAndDuplicateMix() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")
        let single = frame.createNode(.Auxiliary, name: "single")

        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let component: SimulationObjectNameComponent? = world.component(for: object.objectID)
        #expect(component == nil)
        let dupeComponent: SimulationObjectNameComponent? = world.component(for: dupe.objectID)
        #expect(dupeComponent == nil)
        let singleComponent: SimulationObjectNameComponent? = world.component(for: single.objectID)
        #expect(singleComponent?.name == "single")

        #expect(world.objectHasError(object.objectID, error: ModelError.duplicateName("object")))
        #expect(world.objectHasError(dupe.objectID, error: ModelError.duplicateName("object")))
        #expect(!world.objectHasIssues(single.objectID))
    }
}
