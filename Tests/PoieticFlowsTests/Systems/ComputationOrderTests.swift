//
//  ComputationOrder.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct SimulationOrderDependencySystemTests {
    let design: Design
    let frame: TransientPlane
    
    init() throws {
        self.design = Design(metamodel: StockFlowDomain.StockFlowMetamodel)
        self.frame = design.createPlane()
    }
    
    func accept(_ frame: TransientPlane) throws -> World {
        let accepted = try design.accept(frame)
        let world = World(plane: accepted)
        return world
    }
    
    @Test
    func empty() throws {
        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        let component: SimulationOrder = try #require(world.singleton())
        #expect(component.objects.isEmpty)
    }
    
    @Test func basicOrder() throws {
        // a -> b -> c
        let c = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "c", attributes: ["formula": "b"])
        let b = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "b", attributes: ["formula": "a"])
        let a = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "a", attributes: ["formula": "0"])
        
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: a.objectID, target: b.objectID)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: b.objectID, target: c.objectID)
        
        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        let component: SimulationOrder = try #require(world.singleton())

        #expect(component.objects.count == 3)
        #expect(component.objects[0].objectID == a.objectID)
        #expect(component.objects[1].objectID == b.objectID)
        #expect(component.objects[2].objectID == c.objectID)
    }
    @Test func cycle() throws {
        // a <-> b
        let a = frame.createNode(StockFlowDomain.Types.Auxiliary, name:"a", attributes: ["formula": "b"])
        let b = frame.createNode(StockFlowDomain.Types.Auxiliary, name:"b", attributes: ["formula": "a"])
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: a.objectID, target: b.objectID)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: b.objectID, target: a.objectID)

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)
        let component: SimulationOrder? = world.singleton()
        #expect(component == nil)
        
        let aEnt = try #require(world.entity(a.objectID))
        #expect(aEnt.hasIssue(identifier: IssueIdentifier.computationCycle))
        let bEnt = try #require(world.entity(b.objectID))
        #expect(bEnt.hasIssue(identifier: IssueIdentifier.computationCycle))
    }
    @Test func orderWithSpecialAuxiliary() throws {
        // p:Aux -> g:GF -> a:Aux
        let param = frame.createNode(StockFlowDomain.Types.Auxiliary, name: "param", attributes: ["formula": "1"])
        let gf = frame.createNode(StockFlowDomain.Types.GraphicalFunction, name: "gf")
        let aux = frame.createNode(StockFlowDomain.Types.Auxiliary, name:"aux", attributes: ["formula": "gf"])

        frame.createEdge(StockFlowDomain.Types.Parameter, origin: param.objectID, target: gf.objectID)
        frame.createEdge(StockFlowDomain.Types.Parameter, origin: gf.objectID, target: aux.objectID)

        let world = try accept(frame)
        try ComputationOrderSystem.update(world)

        let component: SimulationOrder = try #require(world.singleton())
        #expect(component.objects.count == 3)
        #expect(component.objects[0].objectID == param.objectID)
        #expect(component.objects[1].objectID == gf.objectID)
        #expect(component.objects[2].objectID == aux.objectID)

    }
}
