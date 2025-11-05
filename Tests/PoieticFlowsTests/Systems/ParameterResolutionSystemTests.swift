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
    let frame: TransientFrame

    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }

    func accept(_ frame: TransientFrame) throws -> RuntimeFrame {
        let stable = try design.accept(frame)
        let validated = try design.validate(stable)
        return RuntimeFrame(validated)
    }

    // MARK: - Basic Sanity Tests

    @Test func noComponentForNonFormulaNode() throws {
        // DesignInfo has no formula, so no ResolvedParametersComponent should be created
        let info = frame.create(.DesignInfo, structure: .unstructured)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent? = runtime.component(for: info.objectID)
        #expect(component == nil)
    }

    // MARK: - Formula Tests

    @Test func formulaWithoutParameters() throws {
        // Formula "1 + 1" requires no parameters
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "aux", attributes: ["formula": "1 + 1"])

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent? = runtime.component(for: aux.objectID)
        #expect(component == nil, "No component should be created when no parameters needed")
        #expect(!runtime.objectHasIssues(aux.objectID))
    }

    @Test func formulaWithCorrectParameter() throws {
        // Formula "x" with parameter x connected
        let x = frame.createNode(ObjectType.Auxiliary, name: "x", attributes: ["formula": "10"])
        let aux = frame.createNode(ObjectType.Auxiliary, name: "consumer", attributes: ["formula": "x"])

        frame.createEdge(.Parameter, origin: x, target: aux)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: aux.objectID))
        #expect(component.incoming.count == 1)
        #expect(component.incoming["x"] == aux.objectID)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.isEmpty == true)
        #expect(!runtime.objectHasIssues(aux.objectID))
    }

    @Test func formulaWithMissingParameter() throws {
        // Formula "x" without parameter connection
        let aux = frame.createNode(ObjectType.Auxiliary, name: "consumer", attributes: ["formula": "x"])

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: aux.objectID))
        #expect(component.incoming.isEmpty == true)
        #expect(component.missing == ["x"])
        #expect(component.unused.isEmpty == true)
        #expect(runtime.objectHasError(aux.objectID, error: ModelError.unknownParameter("x")))
    }

    @Test func formulaWithUnusedParameter() throws {
        // Formula "x" with unused parameter "y" connected
        let x = frame.createNode(.Auxiliary, name: "x", attributes: ["formula": "10"])
        let y = frame.createNode(.Auxiliary, name: "y", attributes: ["formula": "20"])
        let aux = frame.createNode(.Auxiliary, name: "consumer", attributes: ["formula": "x"])

        frame.createEdge(.Parameter, origin: x, target: aux)
        frame.createEdge(.Parameter, origin: y, target: aux)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: aux.objectID))
        #expect(component.incoming.count == 1)
        #expect(component.incoming["x"] == aux.objectID)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.count == 1)
        #expect(runtime.objectHasError(aux.objectID, error: ModelError.unusedInput("y")))
    }

    @Test func formulaWithMixedParameters() throws {
        // Formula "a + b" with: a correct, c unused, b missing
        let a = frame.createNode(.Auxiliary, name: "a", attributes: ["formula": "10"])
        let _ = frame.createNode(.Auxiliary, name: "b", attributes: ["formula": "20"])
        let c = frame.createNode(.Auxiliary, name: "c", attributes: ["formula": "30"])
        let aux = frame.createNode(.Auxiliary, name: "consumer", attributes: ["formula": "a + b"])

        frame.createEdge(.Parameter, origin: a, target: aux)
        frame.createEdge(.Parameter, origin: c, target: aux)
        // Note: b is created but not connected

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: aux.objectID))
        #expect(component.incoming.count == 1)
        #expect(component.incoming["a"] == aux.objectID)
        #expect(component.missing == ["b"])
        #expect(component.unused.count == 1)
        #expect(runtime.objectHasError(aux.objectID, error: ModelError.unknownParameter("b")))
        #expect(runtime.objectHasError(aux.objectID, error: ModelError.unusedInput("c")))
    }

    @Test func formulaWithBuiltinVariable() throws {
        // Formula using "time" builtin - should not require connection
        let aux = frame.createNode(.Auxiliary, name: "timer", attributes: ["formula": "time * 2"])

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent? = runtime.component(for: aux.objectID)
        #expect(component == nil, "No component needed when only builtins used")
        #expect(!runtime.objectHasIssues(aux.objectID))
    }

    @Test func formulaWithMultipleCorrectParameters() throws {
        // Formula "x + y + z" with all parameters connected
        let x = frame.createNode(.Auxiliary, name: "x", attributes: ["formula": "1"])
        let y = frame.createNode(.Auxiliary, name: "y", attributes: ["formula": "2"])
        let z = frame.createNode(.Auxiliary, name: "z", attributes: ["formula": "3"])
        let aux = frame.createNode(.Auxiliary, name: "sum", attributes: ["formula": "x + y + z"])

        frame.createEdge(.Parameter, origin: x, target: aux)
        frame.createEdge(.Parameter, origin: y, target: aux)
        frame.createEdge(.Parameter, origin: z, target: aux)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: aux.objectID))
        #expect(component.incoming.count == 3)
        #expect(component.incoming["x"] == aux.objectID)
        #expect(component.incoming["y"] == aux.objectID)
        #expect(component.incoming["z"] == aux.objectID)
        #expect(component.missing.isEmpty == true)
        #expect(component.unused.isEmpty == true)
        #expect(!runtime.objectHasIssues(aux.objectID))
    }

    // MARK: - Delay Tests

    @Test func delayWithoutParameter() throws {
        // Delay node with no parameter - should error
        let delay = frame.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: delay.objectID))
        #expect(component.connectedUnnamed.isEmpty == true)
        #expect(component.missingUnnamed == 1)
        #expect(runtime.objectHasError(delay.objectID, error: ModelError.missingRequiredParameter))
    }

    @Test func delayWithOneParameter() throws {
        // Delay node with one parameter - correct
        let source = frame.createNode(.Auxiliary, name: "source", attributes: ["formula": "100"])
        let delay = frame.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])
        frame.createEdge(.Parameter, origin: source, target: delay)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: delay.objectID))
        #expect(component.connectedUnnamed == [source.objectID])
        #expect(component.missingUnnamed == 0)
        #expect(component.unused.isEmpty == true)
        #expect(!runtime.objectHasIssues(delay.objectID))
    }

    @Test func delayWithTwoParameters() throws {
        let source1 = frame.createNode(.Auxiliary, name: "source1", attributes: ["formula": "100"])
        let source2 = frame.createNode(.Auxiliary, name: "source2", attributes: ["formula": "100"])
        let delay = frame.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])
        frame.createEdge(.Parameter, origin: source1, target: delay)
        frame.createEdge(.Parameter, origin: source2, target: delay)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let component: ResolvedParametersComponent = try #require(runtime.component(for: delay.objectID))
        #expect(component.unused.count == 2)
        #expect(runtime.objectHasError(delay.objectID, error: ModelError.tooManyParameters))
    }

    // MARK: - Other auxiliaries

    @Test func correctOneParameterAuxiliaries() throws {
        let source = frame.createNode(.Auxiliary, name: "source", attributes: ["formula": "100"])
        let gf = frame.createNode(.GraphicalFunction, name: "lookup")
        let delay = frame.createNode(.Delay, name: "delayed", attributes: ["delay_duration": 5])
        let smooth = frame.createNode(.Smooth, name: "smoothed", attributes: ["window_time": 5])

        frame.createEdge(.Parameter, origin: source, target: gf)
        frame.createEdge(.Parameter, origin: source, target: delay)
        frame.createEdge(.Parameter, origin: source, target: smooth)

        let runtime = try accept(frame)

        let parser = ExpressionParserSystem()
        parser.update(runtime)

        let system = ParameterResolutionSystem()
        try system.update(runtime)

        let gfComp: ResolvedParametersComponent = try #require(runtime.component(for: gf.objectID))
        let delayComp: ResolvedParametersComponent = try #require(runtime.component(for: delay.objectID))
        let smoothComp: ResolvedParametersComponent = try #require(runtime.component(for: smooth.objectID))
        #expect(gfComp.connectedUnnamed == [source.objectID])
        #expect(delayComp.connectedUnnamed == [source.objectID])
        #expect(smoothComp.connectedUnnamed == [source.objectID])
        #expect(!runtime.objectHasIssues(gf.objectID))
        #expect(!runtime.objectHasIssues(delay.objectID))
        #expect(!runtime.objectHasIssues(smooth.objectID))
    }
}
