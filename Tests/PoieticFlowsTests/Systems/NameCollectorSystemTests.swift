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
        
        try NameNormalizationSystem.update(world)
        try NameResolutionSystem.update(world)
        return world
    }
    
    @Test func empty() throws {
        let object = frame.createNode(.Note, name: "note")
        
        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameResolutionSystem.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects.isEmpty)
        
        let component: SimulationName? = world.entity(object.objectID)?.component()
        #expect(component == nil)
    }
    
    @Test func trimmedName() throws {
        let object = frame.createNode(.Auxiliary, name: "  object \n")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameResolutionSystem.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects["object"] == object.objectID)

        let component: SimulationName = try #require(world.entity(object.objectID)?.component())
        #expect(component.name == "object")
    }
    @Test func duplicateName() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: " object")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameResolutionSystem.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        let component: SimulationName? = objEnt.component()
        #expect(component == nil)
        #expect(objEnt.hasIssue(identifier: IssueIdentifier.duplicateName))
                

        let dupeEnt = try #require(world.entity(dupe.objectID))
        let dupeComponent: SimulationName? = dupeEnt.component()
        #expect(dupeComponent == nil)
        #expect(dupeEnt.hasIssue(identifier: IssueIdentifier.duplicateName))
    }
    @Test func validAndDuplicateMix() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")
        let single = frame.createNode(.Auxiliary, name: "single")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameResolutionSystem.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        let component: SimulationName? = objEnt.component()
        #expect(component == nil)
        #expect(objEnt.hasIssue(identifier: IssueIdentifier.duplicateName))

        let dupeEnt = try #require(world.entity(dupe.objectID))
        let dupeComponent: SimulationName? = dupeEnt.component()
        #expect(dupeComponent == nil)
        #expect(dupeEnt.hasIssue(identifier: IssueIdentifier.duplicateName))

        let singleEnt = try #require(world.entity(single.objectID))
        let singleComponent: SimulationName? = singleEnt.component()
        #expect(singleComponent?.name == "single")
        #expect(!singleEnt.hasIssues)
    }
}
