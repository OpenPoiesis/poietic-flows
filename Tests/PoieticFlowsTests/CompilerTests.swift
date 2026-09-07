//
//  CompilerTests.swift
//
//
//  Created by Stefan Urbanek on 09/06/2023.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

extension TransientPlane {
    @discardableResult
    public func createEdge(_ type: ObjectType,
                           origin: TransientObject,
                           target: TransientObject,
                           attributes: [String:Variant] = [:]) -> TransientObject {
        precondition(type.topologyType == .edge, "Structural type mismatch")
        precondition(contains(origin.objectID), "Missing edge origin")
        precondition(contains(target.objectID), "Missing edge target")

        let snapshot = create(type, topology: .edge(origin.objectID, target.objectID), attributes: attributes)
        
        return snapshot
    }

}

@Suite struct CompilerTest {
    let design: Design
    let frame: TransientPlane
    let world: World
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createPlane()
        self.world = World(design: design)
        self.world.addSchedule(Schedule(
            label: PlaneChangeSchedule.self,
            systems: SimulationPlanningSystems
        ))
    }
   
    func acceptAndUpdate() throws {
        let accepted = try design.accept(frame)
        world.setPlane(accepted)
        try world.run(schedule: PlaneChangeSchedule.self)
    }
    
    @Test func noComputedVariables() throws {
        try acceptAndUpdate()
        let plan: SimulationPlan = try #require(world.singleton())
        
        #expect(plan.simulationObjects.count == 0)
        #expect(plan.stateVariables.count == BuiltinVariable.allCases.count)
    }
    
    @Test func computedVariables() throws {
        frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "c", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Note, name: "note")
        
        try acceptAndUpdate()
        let plan: SimulationPlan = try #require(world.singleton())
        let names = plan.simulationObjects.map { $0.nameKey } .sorted()
        
        #expect(names == ["a", "b", "c"])
        #expect(plan.stateVariables.count == 3 + BuiltinVariable.allCases.count)
    }
    
    @Test func duplicateName() throws {
        // Testing whether the planner picks-up the InvalidName tag (regression after name normalisation)
        frame.createNode(ObjectType.Auxiliary, name: "x", attributes: ["formula": "10"])
        frame.createNode(ObjectType.Auxiliary, name: "x", attributes: ["formula": "20"])
        
        try acceptAndUpdate()
        let plan: SimulationPlan? = world.singleton()
        #expect(plan == nil)
    }

    @Test func reservedName() throws {
        // Testing whether the planner picks-up the InvalidName tag (regression after name normalisation)
        frame.createNode(ObjectType.Auxiliary, name: "time", attributes: ["formula": "10"])
        
        try acceptAndUpdate()
        let plan: SimulationPlan? = world.singleton()
        #expect(plan == nil)
    }

    @Test func badFunctionName() throws {
        let aux = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "nonexistent(10)"])
        
        try acceptAndUpdate()
        let plan: SimulationPlan? = world.singleton()
        #expect(plan == nil)

        let entity = try #require(world.entity(aux.objectID))
        #expect(entity.hasIssue(identifier: "expression.unknown_function",
                                details: ["function": "nonexistent"]))
    }

    @Test func singleComputedVariable() throws {
        let _ = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "if(time < 2, 0, 1)"])
        
        try acceptAndUpdate()
        let plan: SimulationPlan = try #require(world.singleton())
        let names = plan.simulationObjects.map { $0.nameKey }.sorted()
        
        #expect(names == ["a"])
    }

    @Test func inflowOutflow() throws {
        let a = frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "1"])
        let b = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])

        frame.createEdge(ObjectType.Flow, origin: a, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: b)
        
        try acceptAndUpdate()
        let plan: SimulationPlan = try #require(world.singleton())

        let aIndex = try #require(plan.stocks.firstIndex { $0.objectID == a.objectID })
        let bIndex = try #require(plan.stocks.firstIndex { $0.objectID == b.objectID })

        #expect(plan.stocks.count == 2)
        #expect(plan.stocks[aIndex].objectID == a.objectID)
        #expect(plan.stocks[aIndex].inflows == [])
        
        let index = try #require(plan.flows.firstIndex { $0.objectID == flow.objectID })
        #expect(plan.stocks[aIndex].outflows == [index])

        #expect(plan.stocks[bIndex].objectID == b.objectID)
        #expect(plan.stocks[bIndex].inflows == [index])
        #expect(plan.stocks[bIndex].outflows == [])
    }
    
    @Test func disconnectedGraphicalFunction() throws {
        let gf = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g")

        try acceptAndUpdate()
        let plan: SimulationPlan? = world.singleton()
        #expect(plan == nil)
        let entity = try #require(world.entity(gf.objectID))
        #expect(entity.hasIssue(identifier: "missing_required_parameter"))
    }

    @Test func graphicalFunctionComputation() throws {
        let points = [Point(x:0, y:0), Point(x: 10, y:10)]
        let p = frame.createNode(ObjectType.Auxiliary, name:"p", attributes: ["formula": "0"])
        let gf = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g",
                                  attributes: ["graphical_function_points": Variant(points)])
        let aux = frame.createNode(ObjectType.Auxiliary, name:"a", attributes: ["formula": "g"])

        frame.createEdge(ObjectType.Parameter, origin: p, target: gf)
        frame.createEdge(ObjectType.Parameter, origin: gf, target: aux)

        try acceptAndUpdate()
        let plan: SimulationPlan = try #require(world.singleton())
        let object = try #require(plan.simulationObject(gf.objectID),
                                  "No compiled variable for the graphical function")

        switch object.computation {
        case .graphicalFunction(let fn):
            #expect(fn.function.points == points)
        default:
            Issue.record("Graphical function compiled as: \(object.computation)")
        }
    }
}
