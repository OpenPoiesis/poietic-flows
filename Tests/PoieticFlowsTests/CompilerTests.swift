//
//  CompilerTests.swift
//
//
//  Created by Stefan Urbanek on 09/06/2023.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

extension CompilerError {
    func objectHasIssue(_ objectID: ObjectID, identifier: String) -> Bool {
        guard let issues = objectIssues(objectID) else { return false }
        return issues.contains { $0.identifier == identifier }
    }

    func objectHasError<T:IssueProtocol>(_ objectID: ObjectID, error: T) -> Bool {
        guard let issues = objectIssues(objectID) else { return false }
        for issue in issues {
            if let objectError = issue.error as? T {
                return objectError == error
            }
        }
        return false
    }

    func objectIssues(_ objectID: ObjectID) -> [PoieticCore.Issue]? {
        switch self {
        case .internalError(_): return nil
        case .issues(let issues): return issues[objectID]
        }
        
    }
}

extension TransientFrame {
    @discardableResult
    public func createEdge(_ type: ObjectType,
                           origin: TransientObject,
                           target: TransientObject,
                           attributes: [String:Variant] = [:]) -> TransientObject {
        precondition(type.structuralType == .edge, "Structural type mismatch")
        precondition(contains(origin.objectID), "Missing edge origin")
        precondition(contains(target.objectID), "Missing edge target")

        let snapshot = create(type, structure: .edge(origin.objectID, target.objectID), attributes: attributes)
        
        return snapshot
    }

}

@Suite struct CompilerTest {
    let design: Design
    let frame: TransientFrame
    
    init() throws {
        self.design = Design(metamodel: StockFlowMetamodel)
        self.frame = design.createFrame()
    }
    
    @Test func noComputedVariables() throws {
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let plan = try compiler.compile()
        
        #expect(plan.simulationObjects.count == 0)
        #expect(plan.stateVariables.count == BuiltinVariable.allCases.count)
    }
    
    @Test func computedVariables() throws {
        frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock, name: "c", attributes: ["formula": "0"])
        frame.createNode(ObjectType.Note, name: "note")
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let plan = try compiler.compile()
        let names = plan.simulationObjects.map { $0.name } .sorted()
        
        #expect(names == ["a", "b", "c"])
        #expect(plan.stateVariables.count == 3 + BuiltinVariable.allCases.count)
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
            return error.objectHasError(aux.objectID,
                                        error: ExpressionError.unknownFunction("nonexistent"))
        }
    }

    @Test func singleComputedVariable() throws {
        let _ = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "if(time < 2, 0, 1)"])
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()
        let names = compiled.simulationObjects.map { $0.name }.sorted()
        
        #expect(names == ["a"])
    }

    @Test func inflowOutflow() throws {
        let a = frame.createNode(ObjectType.Stock, name: "a", attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.FlowRate, name: "f", attributes: ["formula": "1"])
        let b = frame.createNode(ObjectType.Stock, name: "b", attributes: ["formula": "0"])

        frame.createEdge(ObjectType.Flow, origin: a, target: flow)
        frame.createEdge(ObjectType.Flow, origin: flow, target: b)
        
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        let compiled = try compiler.compile()
        
        let aIndex = try #require(compiled.stocks.firstIndex { $0.objectID == a.objectID })
        let bIndex = try #require(compiled.stocks.firstIndex { $0.objectID == b.objectID })

        #expect(compiled.stocks.count == 2)
        #expect(compiled.stocks[aIndex].objectID == a.objectID)
        #expect(compiled.stocks[aIndex].inflows == [])
        #expect(compiled.stocks[aIndex].outflows == [compiled.flowIndex(flow.objectID)])

        #expect(compiled.stocks[bIndex].objectID == b.objectID)
        #expect(compiled.stocks[bIndex].inflows == [compiled.flowIndex(flow.objectID)])
        #expect(compiled.stocks[bIndex].outflows == [])
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

            return error.objectHasIssue(gf.objectID, identifier: "missing_required_parameter")
        }
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
        let object = try #require(compiled.simulationObject(gf.objectID),
                                  "No compiled variable for the graphical function")

        switch object.computation {
        case .graphicalFunction(let fn):
            #expect(fn.function.points == points)
        default:
            Issue.record("Graphical function compiled as: \(object.computation)")
        }
    }

    @Test func syntaxErrorIsNotInternalError() throws {
        let a = frame.createNode(ObjectType.Auxiliary,
                                 name:"a",
                                 attributes: ["formula": "10 + "])
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        #expect {
            try compiler.compile()
        } throws: {
            guard let error = $0 as? CompilerError else {
                Issue.record("Unexpected error: \($0)")
                return false
            }
            return error.objectHasIssue(a.objectID, identifier: "syntax_error")
        }
    }
}
