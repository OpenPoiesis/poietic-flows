//
//  NameValidationSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct NameValidationSystemTests {
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
        try NameValidationSystem.update(world)
        return world
    }
    
    @Test func empty() throws {
        let object = frame.createNode(.Note, name: "note")
        
        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameValidationSystem.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects.isEmpty)
    }
    
    @Test func trimmedName() throws {
        let object = frame.createNode(.Auxiliary, name: "  object \n")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameValidationSystem.update(world)
        
        let lookup: SimulationNameLookup = try #require(world.singleton())
        #expect(lookup.namedObjects["object"] == object.objectID)
    }
    
    @Test func duplicateName() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: " object")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameValidationSystem.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        #expect(objEnt.hasIssue(identifier: IssueIdentifier.duplicateName))
        #expect(objEnt.contains(InvalidName.self))
                

        let dupeEnt = try #require(world.entity(dupe.objectID))
        #expect(dupeEnt.hasIssue(identifier: IssueIdentifier.duplicateName))
        #expect(dupeEnt.contains(InvalidName.self))
    }
    
    @Test func reservedName() throws {
        let object = frame.createNode(.Auxiliary, name: "time")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameValidationSystem.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        #expect(objEnt.hasIssue(identifier: IssueIdentifier.reservedName))
        #expect(objEnt.contains(InvalidName.self))
    }

    @Test func validAndDuplicateMix() throws {
        let object = frame.createNode(.Auxiliary, name: "object")
        let dupe = frame.createNode(.Auxiliary, name: "object")
        let single = frame.createNode(.Auxiliary, name: "single")

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        try NameValidationSystem.update(world)
        
        let objEnt = try #require(world.entity(object.objectID))
        #expect(objEnt.hasIssue(identifier: IssueIdentifier.duplicateName))

        let dupeEnt = try #require(world.entity(dupe.objectID))
        #expect(dupeEnt.hasIssue(identifier: IssueIdentifier.duplicateName))

        let singleEnt = try #require(world.entity(single.objectID))
        #expect(!singleEnt.hasIssues)
    }
}
