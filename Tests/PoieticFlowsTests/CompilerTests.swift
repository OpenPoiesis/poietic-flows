//
//  CompilerTests.swift
//
//
//  Created by Stefan Urbanek on 09/06/2023.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

extension TransientFrame {
    @discardableResult
    public func createEdge(_ type: ObjectType,
                           origin: MutableObject,
                           target: MutableObject,
                           attributes: [String:Variant] = [:]) -> MutableObject {
        precondition(type.structuralType == .edge, "Structural type mismatch")
        precondition(contains(origin.id), "Missing edge origin")
        precondition(contains(target.id), "Missing edge target")

        let snapshot = create(type, structure: .edge(origin.id, target.id), attributes: attributes)
        
        return snapshot
    }

}

@Suite struct CompilerTest {
    let design: Design
    let frame: TransientFrame
    
    init() throws {
        self.design = Design(metamodel: FlowsMetamodel)
        self.frame = design.createFrame()
    }
    
    @Test func noComputedVariables() throws {
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let model = try compiler.compile()
        
        #expect(model.simulationObjects.count == 0)
        #expect(model.stateVariables.count == BuiltinVariable.allCases.count)
    }
    
    @Test func computedVariables() throws {
        frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "c", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Note, name: "note")
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()
        let names = compiled.simulationObjects.map { $0.name } .sorted()
        
        #expect(names == ["a", "b", "c"])
        #expect(compiled.stateVariables.count == 3 + BuiltinVariable.allCases.count)
    }
    
    @Test func sortedNodes() throws {
        // a -> b -> c
        let c = frame.createNode(ObjectType.Auxiliary, name: "c", attributes: ["formula": "b"])
        let b = frame.createNode(ObjectType.Auxiliary, name: "b", attributes: ["formula": "a"])
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Parameter, origin: a, target: b)
        frame.createEdge(ObjectType.Parameter, origin: b, target: c)
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()

        let sorted = compiled.simulationObjects
        
        #expect(sorted.count == 3)
        #expect(sorted[0].id == a.id)
        #expect(sorted[1].id == b.id)
        #expect(sorted[2].id == c.id)
    }

    @Test func badFunctionName() throws {
        let aux = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "nonexistent(10)"])
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        #expect {
            try compiler.compile()
        } throws: {
            guard let error = $0 as? CompilerError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            guard case .issues(let issues) = error else {
                Issue.record("Unexpected error type: \($0)")
                return false
            }
            guard let objectIssues = issues[aux.id] else {
                Issue.record("Expected object issues, foud none")
                return false
            }
            return objectIssues.count == 1
                    && objectIssues.first == .expressionError(.unknownFunction("nonexistent"))
        }
    }

    @Test func singleComputedVariable() throws {
        let _ = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "if(time < 2, 0, 1)"])
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()
        let names = compiled.simulationObjects.map { $0.name }.sorted()
        
        #expect(names == ["a"])
    }

    @Test func duplicateNames() throws {
        let c1 = frame.createNode(ObjectType.Stock, name: "things", attributes: ["formula": "0"])
        let c2 = frame.createNode(ObjectType.Stock, name: "things", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])

        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        #expect {
            try compiler.compile()
        } throws: {
            guard let error = $0 as? CompilerError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            guard case .issues(let issues) = error else {
                Issue.record("Unexpected error type: \($0)")
                return false
            }
            return issues[c1.id]?.count == 1
                    && issues[c2.id]?.count == 1
        }
    }
    
    @Test func inflowOutflow() throws {
        let source = frame.createNode(ObjectType.Stock, name: "source", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "1"])
        let sink = frame.createNode(ObjectType.Stock, name: "sink", attributes: ["formula": "0"])

        frame.createEdge(ObjectType.Flow, origin: source, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: sink)
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()
        
        #expect(compiled.stocks.count == 2)
        #expect(compiled.stocks[0].id == source.id)
        #expect(compiled.stocks[0].inflows == [])
        #expect(compiled.stocks[0].outflows == [compiled.variableIndex(of: flow.id)])

        #expect(compiled.stocks[1].id == sink.id)
        #expect(compiled.stocks[1].inflows == [compiled.variableIndex(of: flow.id)])
        #expect(compiled.stocks[1].outflows == [])
    }
    
    @Test func disconnectedGraphicalFunction() throws {
        let gf = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g")

        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        #expect {
            try compiler.compile()
        } throws: {
            guard let error = $0 as? CompilerError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            guard case .issues(let allIssues) = error else {
                Issue.record("Unexpected error type: \($0)")
                return false
            }

            guard let issues = allIssues[gf.id]else {
                Issue.record("Issues expected, got none")
                return false
            }

            return $0 is CompilerError
                    && issues.count == 1
                    && issues.first == ObjectIssue.missingRequiredParameter
        }
    }

    @Test func graphicalFunctionNameReferences() throws {
        let param = frame.createNode(ObjectType.Auxiliary, name: "p", attributes: ["formula": "1"])
        let gf = frame.createNode(ObjectType.GraphicalFunction, name: "g")
        let aux = frame.createNode(ObjectType.Auxiliary, name:"a", attributes: ["formula": "g"])

        frame.createEdge(ObjectType.Parameter, origin: param, target: gf)
        frame.createEdge(ObjectType.Parameter, origin: gf, target: aux)

        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()

        let funcs = compiled.graphicalFunctions
        #expect(funcs.count == 1)

        let boundFn = funcs.first!
        #expect(boundFn.parameterIndex == compiled.variableIndex(of:param.id))

        #expect(compiled.simulationObjects.contains { $0.name == "g" })
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

        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()
        let object = try #require(compiled.simulationObject(gf.id),
                                  "No compiled variable for the graphical function")

        switch object.computation {
        case .graphicalFunction(let fn):
            #expect(fn.function.points == points)
        default:
            Issue.record("Graphical function compiled as: \(object.computation)")
        }
    }

    @Test func graphCycleError() throws {
        let a = frame.createNode(ObjectType.Auxiliary, name:"a", attributes: ["formula": "b"])
        let b = frame.createNode(ObjectType.Auxiliary, name:"b", attributes: ["formula": "a"])
        frame.createEdge(ObjectType.Parameter, origin: a, target: b)
        frame.createEdge(ObjectType.Parameter, origin: b, target: a)
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        #expect {
            try compiler.compile()
        } throws: {
            guard let error = $0 as? CompilerError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            guard case .issues(let issues) = error else {
                Issue.record("Unexpected error type: \($0)")
                return false
            }

            return $0 is CompilerError
                    && issues[a.id]?.first == ObjectIssue.computationCycle
                    && issues[b.id]?.first == ObjectIssue.computationCycle
        }
    }
    
    @Test func stockCycleError() throws {
        let a = frame.createNode(ObjectType.Stock, name:"a", attributes: ["formula": "0"])
        let b = frame.createNode(ObjectType.Stock, name:"b", attributes: ["formula": "0"])
        let fab = frame.createNode(ObjectType.FlowRate, name: "fab", attributes: ["formula": "0"])
        let fba = frame.createNode(ObjectType.FlowRate, name: "fba", attributes: ["formula": "0"])
        frame.createEdge(ObjectType.Flow, origin: a, target: fab)
        frame.createEdge(ObjectType.Flow, origin: fab, target: b)
        frame.createEdge(ObjectType.Flow, origin: b, target: fba)
        frame.createEdge(ObjectType.Flow, origin: fba, target: a)

        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        #expect {
            try compiler.compile()
        } throws: {
            guard let error = $0 as? CompilerError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            guard case .issues(let issues) = error else {
                Issue.record("Unexpected error type: \($0)")
                return false
            }
            return $0 is CompilerError
                    && issues[a.id]?.first == ObjectIssue.flowCycle
                    && issues[b.id]?.first == ObjectIssue.flowCycle
        }
    }
    
    @Test func delayedInflowBreaksTheCycle() throws {
        let a = frame.createNode(ObjectType.Stock, name:"a",
                                 attributes: [ "formula": "0", "delayed_inflow": Variant(true) ])
        let b = frame.createNode(ObjectType.Stock, name:"b", attributes: ["formula": "0"])
        let fab = frame.createNode(ObjectType.FlowRate, name: "fab", attributes: ["formula": "0"])
        let fba = frame.createNode(ObjectType.FlowRate, name: "fba", attributes: ["formula": "0"])
        
        frame.createEdge(ObjectType.Flow, origin: a, target: fab)
        frame.createEdge(ObjectType.Flow, origin: fab, target: b)
        frame.createEdge(ObjectType.Flow, origin: b, target: fba)
        frame.createEdge(ObjectType.Flow, origin: fba, target: a)

        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        // Test no throw
        let _ = try compiler.compile()
    }
}
