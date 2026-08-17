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
    let frame: TransientPlane
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createPlane()
    }
    
    func accept(_ frame: TransientPlane) throws -> World {
        let accepted = try design.accept(frame)
        let world = World(plane: accepted)
        
        let system = ComputationOrderSystem(world)
        try system.update(world)
        return world
    }
    
    @Test func empty() throws {
        let object = frame.createNode(.Note, name: "note")
        
        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects.isEmpty)
        
        let component: SimulationName? = world.entity(object.objectID)?.component()
        #expect(component == nil)
    }
    
    @Test func emptyNames() throws {
        let empty = frame.createNode(.Auxiliary, name: "")
        let whitespace = frame.createNode(.Auxiliary, name: " \t\n\r")
        
        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects.isEmpty)
        
        let emptyEnt = try #require(world.entity(empty.objectID))
        #expect(emptyEnt.hasError(ModelError.emptyName))
        let wsEnt = try #require(world.entity(whitespace.objectID))
        #expect(wsEnt.hasError(ModelError.emptyName))
        
        let component1: SimulationName? = world.entity(empty.objectID)?.component()
        #expect(component1 == nil)
        let component2: SimulationName? = world.entity(whitespace.objectID)?.component()
        #expect(component2 == nil)
    }
    
    @Test func trimmedName() throws {
        let object = frame.createNode(.Auxiliary, name: "  object \n")

        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects["object"] == object.objectID)

        let component: SimulationName = try #require(world.entity(object.objectID)?.component())
        #expect(component.name == "object")
    }
    @Test func duplicateName() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")

        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        let component: SimulationName? = objEnt.component()
        #expect(component == nil)
        #expect(objEnt.hasError(ModelError.duplicateName("object")))

        let dupeEnt = try #require(world.entity(dupe.objectID))
        let dupeComponent: SimulationName? = dupeEnt.component()
        #expect(dupeComponent == nil)
        #expect(dupeEnt.hasError(ModelError.duplicateName("object")))
    }
    @Test func validAndDuplicateMix() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")
        let single = frame.createNode(.Auxiliary, name: "single")

        let world = try accept(frame)
        let system = NameResolutionSystem(world)
        try system.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        let component: SimulationName? = objEnt.component()
        #expect(component == nil)
        #expect(objEnt.hasError(ModelError.duplicateName("object")))

        let dupeEnt = try #require(world.entity(dupe.objectID))
        let dupeComponent: SimulationName? = dupeEnt.component()
        #expect(dupeComponent == nil)
        #expect(dupeEnt.hasError(ModelError.duplicateName("object")))

        let singleEnt = try #require(world.entity(single.objectID))
        let singleComponent: SimulationName? = singleEnt.component()
        #expect(singleComponent?.name == "single")
        #expect(!singleEnt.hasIssues)
    }
}
