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
    let frame: TransientFrame
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }
    
    func accept(_ frame: TransientFrame) throws -> RuntimeFrame {
        let accepted = try design.accept(frame)
        let runtime = RuntimeFrame(accepted)
        return runtime
    }
    
    @Test
    func empty() throws {
        let runtime = try accept(frame)
        let system = ComputationOrderSystem()
        try system.update(runtime)
        let component = try #require(runtime.frameComponent(SimulationOrderComponent.self))
        #expect(component.objects.isEmpty)
    }
    
    @Test func basicOrder() throws {
        // a -> b -> c
        let c = frame.createNode(ObjectType.Auxiliary, name: "c", attributes: ["formula": "b"])
        let b = frame.createNode(ObjectType.Auxiliary, name: "b", attributes: ["formula": "a"])
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Parameter, origin: a, target: b)
        frame.createEdge(ObjectType.Parameter, origin: b, target: c)
        
        let runtime = try accept(frame)
        let system = ComputationOrderSystem()
        try system.update(runtime)
        let component = try #require(runtime.frameComponent(SimulationOrderComponent.self))
        
        #expect(component.objects.count == 3)
        #expect(component.objects[0].objectID == a.objectID)
        #expect(component.objects[1].objectID == b.objectID)
        #expect(component.objects[2].objectID == c.objectID)
    }
    @Test func cycle() throws {
        // a <-> b
        let a = frame.createNode(ObjectType.Auxiliary, name:"a", attributes: ["formula": "b"])
        let b = frame.createNode(ObjectType.Auxiliary, name:"b", attributes: ["formula": "a"])
        frame.createEdge(ObjectType.Parameter, origin: a, target: b)
        frame.createEdge(ObjectType.Parameter, origin: b, target: a)

        let runtime = try accept(frame)
        let system = ComputationOrderSystem()
        try system.update(runtime)
        let component = runtime.frameComponent(SimulationOrderComponent.self)
        #expect(component == nil)
        
        #expect(runtime.objectHasError(a.objectID, error: ModelError.computationCycle))
        #expect(runtime.objectHasError(b.objectID, error: ModelError.computationCycle))
    }
    @Test func orderWithSpecialAuxiliary() throws {
        // p:Aux -> g:GF -> a:Aux
        let param = frame.createNode(ObjectType.Auxiliary, name: "param", attributes: ["formula": "1"])
        let gf = frame.createNode(ObjectType.GraphicalFunction, name: "gf")
        let aux = frame.createNode(ObjectType.Auxiliary, name:"aux", attributes: ["formula": "gf"])

        frame.createEdge(ObjectType.Parameter, origin: param, target: gf)
        frame.createEdge(ObjectType.Parameter, origin: gf, target: aux)

        let runtime = try accept(frame)
        let system = ComputationOrderSystem()
        try system.update(runtime)

        let component = try #require(runtime.frameComponent(SimulationOrderComponent.self))
        #expect(component.objects.count == 3)
        #expect(component.objects[0].objectID == param.objectID)
        #expect(component.objects[1].objectID == gf.objectID)
        #expect(component.objects[2].objectID == aux.objectID)

    }
}
