//
//  ParameterResolutionSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct ParameterResolutionSystemTests {
    let design: Design
    let plane: TransientPlane

    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.plane = design.createPlane()
    }

    func accept(_ plane: TransientPlane) throws -> World {
        let accepted = try design.accept(plane)
        return World(plane: accepted)
    }
    
    func update(_ world: World) throws {
        try NameNormalizationSystem.update(world)
        try ExpressionParserSystem.update(world)
        try ParameterResolutionSystem.update(world)
    }
    
    // MARK: - Basic Sanity Tests

    @Test func noComponentForNonFormulaNode() throws {
        // DesignInfo has no formula, so no ResolvedParametersComponent should be created
        let info = plane.create(.DesignInfo, topology: .unstructured)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(info.objectID))
        let component: ResolvedParameters? = entity.component()
        #expect(component == nil)
    }

    // MARK: - Formula Tests

    @Test func formulaWithoutParameters() throws {
        // Formula "1 + 1" requires no parameters
        let aux = plane.createNode(ObjectType.Auxiliary,
                                   name: "aux", attributes: ["formula": "1 + 1"])

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters? = entity.component()
        #expect(component == nil, "No component should be created when no parameters needed")
        #expect(!entity.hasIssues)
    }

    @Test func formulaWithCorrectParameter() throws {
        // Formula "x" with parameter x connected
        let x = plane.createNode(ObjectType.Auxiliary, name: "x", attributes: ["formula": "10"])
        let aux = plane.createNode(ObjectType.Auxiliary, name: "consumer", attributes: ["formula": "x"])

        plane.createEdge(.Parameter, origin: x, target: aux)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connected.count == 1)
        #expect(component.connected["x"] == x.objectID)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.isEmpty == true)
        #expect(!entity.hasIssues)
    }
    
    @Test func formulaWithCorrectNormalizedParameter() throws {
        // Formula "x" with parameter x connected
        let pg = plane.createNode(ObjectType.Auxiliary, name: "population \n growth", attributes: ["formula": "10"])
        let x = plane.createNode(ObjectType.Auxiliary, name: "x", attributes: ["formula": "population_growth"])

        plane.createEdge(.Parameter, origin: pg, target: x)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(x.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connected.count == 1)
        #expect(component.connected["population_growth"] == pg.objectID)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.isEmpty == true)
        #expect(!entity.hasIssues)
    }

    @Test func formulaWithQuotedParameters() throws {
        // Formula "x" with parameter x connected
        let pg = plane.createNode(ObjectType.Auxiliary, name: "population  growth", attributes: ["formula": "10"])
        let x = plane.createNode(ObjectType.Auxiliary, name: "x", attributes: ["formula": "population_growth"])
        let y = plane.createNode(ObjectType.Auxiliary, name: "y", attributes: ["formula": "{Population Growth}"])
        let z = plane.createNode(ObjectType.Auxiliary, name: "z", attributes: ["formula": "{ Population growth }"])

        plane.createEdge(.Parameter, origin: pg, target: x)
        plane.createEdge(.Parameter, origin: pg, target: y)
        plane.createEdge(.Parameter, origin: pg, target: z)

        let world = try accept(plane)
        try update(world)

        let xEnt = try #require(world.entity(x.objectID))
        let xComp: ResolvedParameters = try #require(xEnt.component())
        #expect(xComp.connected["population_growth"] == pg.objectID)
        #expect(!xEnt.hasIssues)

        let yEnt = try #require(world.entity(y.objectID))
        let yComp: ResolvedParameters = try #require(yEnt.component())
        #expect(yComp.connected["population_growth"] == pg.objectID)
        #expect(!yEnt.hasIssues)

        let zEnt = try #require(world.entity(z.objectID))
        let zComp: ResolvedParameters = try #require(zEnt.component())
        #expect(zComp.connected["population_growth"] == pg.objectID)
        #expect(!zEnt.hasIssues)
    }

    @Test func formulaWithMissingParameter() throws {
        // Formula "x" without parameter connection
        let aux = plane.createNode(ObjectType.Auxiliary, name: "consumer", attributes: ["formula": "x"])

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connected.isEmpty == true)
        #expect(component.missing == ["x"])
        #expect(component.unused.isEmpty == true)
        #expect(entity.hasIssue(identifier: IssueIdentifier.unknownParameter,
                                details: ["parameter": "x"]))
    }

    @Test func formulaWithUnusedParameter() throws {
        // Formula "x" with unused parameter "y" connected
        let x = plane.createNode(.Auxiliary, name: "x", attributes: ["formula": "10"])
        let y = plane.createNode(.Auxiliary, name: "y", attributes: ["formula": "20"])
        let aux = plane.createNode(.Auxiliary, name: "consumer", attributes: ["formula": "x"])

        plane.createEdge(.Parameter, origin: x, target: aux)
        plane.createEdge(.Parameter, origin: y, target: aux)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connected.count == 1)
        #expect(component.connected["x"] == x.objectID)
        #expect(component.connected["y"] == nil)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.count == 1)
        #expect(entity.hasIssue(identifier: IssueIdentifier.unusedInput,
                                details: ["parameter": "y"]))
    }

    @Test func formulaWithMixedParameters() throws {
        // Formula "a + b" with: a correct, c unused, b missing
        let a = plane.createNode(.Auxiliary, name: "a", attributes: ["formula": "10"])
        let _ = plane.createNode(.Auxiliary, name: "b", attributes: ["formula": "20"])
        let c = plane.createNode(.Auxiliary, name: "c", attributes: ["formula": "30"])
        let aux = plane.createNode(.Auxiliary, name: "consumer", attributes: ["formula": "a + b"])

        plane.createEdge(.Parameter, origin: a, target: aux)
        plane.createEdge(.Parameter, origin: c, target: aux)
        // Note: b is created but not connected

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connected.count == 1)
        #expect(component.connected["a"] == a.objectID)
        #expect(component.missing == ["b"])
        #expect(component.unused.count == 1)
        #expect(entity.hasIssue(identifier: IssueIdentifier.unknownParameter,
                                details: ["parameter": "b"]))
        #expect(entity.hasIssue(identifier: IssueIdentifier.unusedInput,
                                details: ["parameter": "c"]))
    }

    @Test func formulaWithBuiltinVariable() throws {
        // Formula using "time" builtin - should not require connection
        let aux = plane.createNode(.Auxiliary, name: "timer", attributes: ["formula": "time * 2"])

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters? = entity.component()
        #expect(component == nil, "No component needed when only builtins used")
        #expect(!entity.hasIssues)
    }

    @Test func formulaWithMultipleCorrectParameters() throws {
        // Formula "x + y + z" with all parameters connected
        let x = plane.createNode(.Auxiliary, name: "x", attributes: ["formula": "1"])
        let y = plane.createNode(.Auxiliary, name: "y", attributes: ["formula": "2"])
        let z = plane.createNode(.Auxiliary, name: "z", attributes: ["formula": "3"])
        let aux = plane.createNode(.Auxiliary, name: "sum", attributes: ["formula": "x + y + z"])

        plane.createEdge(.Parameter, origin: x, target: aux)
        plane.createEdge(.Parameter, origin: y, target: aux)
        plane.createEdge(.Parameter, origin: z, target: aux)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(aux.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connected.count == 3)
        #expect(component.connected["x"] == x.objectID)
        #expect(component.connected["y"] == y.objectID)
        #expect(component.connected["z"] == z.objectID)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.isEmpty == true)
        #expect(!entity.hasIssues)
    }

    // MARK: - Delay Tests

    @Test func delayWithoutParameter() throws {
        // Delay node with no parameter - should error
        let delay = plane.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(delay.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connectedUnnamed.isEmpty == true)
        #expect(component.missingUnnamed == 1)
        #expect(entity.hasIssue(identifier: IssueIdentifier.missingRequiredParameter))
    }

    @Test func delayWithOneParameter() throws {
        // Delay node with one parameter - correct
        let source = plane.createNode(.Auxiliary, name: "source", attributes: ["formula": "100"])
        let delay = plane.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])
        plane.createEdge(.Parameter, origin: source, target: delay)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(delay.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.connectedUnnamed == [source.objectID])
        #expect(component.missingUnnamed == 0)
        #expect(component.unused.isEmpty == true)
        #expect(!entity.hasIssues)
    }

    @Test func delayWithTwoParameters() throws {
        let source1 = plane.createNode(.Auxiliary, name: "source1", attributes: ["formula": "100"])
        let source2 = plane.createNode(.Auxiliary, name: "source2", attributes: ["formula": "100"])
        let delay = plane.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])
        plane.createEdge(.Parameter, origin: source1, target: delay)
        plane.createEdge(.Parameter, origin: source2, target: delay)

        let world = try accept(plane)
        try update(world)

        let entity = try #require(world.entity(delay.objectID))
        let component: ResolvedParameters = try #require(entity.component())
        #expect(component.unused.count == 2)
        #expect(entity.hasIssue(identifier: IssueIdentifier.tooManyParameters))
    }

    // MARK: - Other auxiliaries

    @Test func correctOneParameterAuxiliaries() throws {
        let source = plane.createNode(.Auxiliary, name: "source", attributes: ["formula": "100"])
        let gf = plane.createNode(.GraphicalFunction, name: "lookup")
        let delay = plane.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])
        let smooth = plane.createNode(.Smooth, name: "smoothed", attributes: ["window_time": 5])

        plane.createEdge(.Parameter, origin: source, target: gf)
        plane.createEdge(.Parameter, origin: source, target: delay)
        plane.createEdge(.Parameter, origin: source, target: smooth)

        let world = try accept(plane)
        try update(world)

        let gfEnt = try #require(world.entity(gf.objectID))
        let gfComp: ResolvedParameters = try #require(gfEnt.component())
        #expect(gfComp.connectedUnnamed == [source.objectID])
        #expect(!gfEnt.hasIssues)
        
        let delayEnt = try #require(world.entity(delay.objectID))
        let delayComp: ResolvedParameters = try #require(delayEnt.component())
        #expect(delayComp.connectedUnnamed == [source.objectID])
        #expect(!delayEnt.hasIssues)

        let smoothEnt = try #require(world.entity(smooth.objectID))
        let smoothComp: ResolvedParameters = try #require(smoothEnt.component())
        #expect(smoothComp.connectedUnnamed == [source.objectID])
        #expect(!smoothEnt.hasIssues)
    }
}
