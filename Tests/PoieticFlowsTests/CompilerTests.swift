//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 09/06/2023.
//

import XCTest
@testable import PoieticFlows
@testable import PoieticCore

final class TestCompiler: XCTestCase {
    var design: Design!
    var frame: TransientFrame!
    
    override func setUp() {
        design = Design(metamodel: FlowsMetamodel)
        frame = design.createFrame()
    }
    
    func testNoComputedVariables() throws {
        // TODO: Check using violation checker
        let compiler = Compiler(frame: try design.accept(frame))
        let model = try compiler.compile()
        
        XCTAssertEqual(model.simulationObjects.count, 0)
        XCTAssertEqual(model.stateVariables.count,
                       Simulator.BuiltinVariables.count)
    }
    
    func testComputedVariables() throws {
        frame.createNode(ObjectType.Stock,
                         name: "a",
                         attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock,
                         name: "b",
                         attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock,
                         name: "c",
                         attributes: ["formula": "0"])
        frame.createNode(ObjectType.Note,
                         name: "note",
                         components: [])
        // TODO: Check using violation checker
        
        let compiler = Compiler(frame: try design.accept(frame))
        let compiled = try compiler.compile()
        let names = compiled.simulationObjects.map { $0.name }
            .sorted()
        
        XCTAssertEqual(names, ["a", "b", "c"])
        XCTAssertEqual(compiled.stateVariables.count,
                       3 + Simulator.BuiltinVariables.count)
    }
    func testBadFunctionName() throws {
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name: "a",
                                   attributes: ["formula": "nonexistent(10)"])
        
        let compiler = Compiler(frame: try design.accept(frame))
        XCTAssertThrowsError(try compiler.compile()) {
            guard $0 as? CompilerError != nil else {
                XCTFail("Expected DomainError, got: \($0)")
                return
            }
            let issues = compiler.issues(for: aux)
            guard let first = issues.first else {
                XCTFail("Expected an issue")
                return
            }
            
            XCTAssertEqual(issues.count, 1)

            guard let issue = first as? NodeIssue else {
                XCTFail("Did not get expected node issue error type")
                return
            }
            XCTAssertEqual(issue, NodeIssue.expressionError(.unknownFunction("nonexistent")))
 
        }
    }
    func testSingleComputedVariable() throws {
        let _ = frame.createNode(ObjectType.Auxiliary,
                                   name: "a",
                                   attributes: ["formula": "if(time < 2, 0, 1)"])
        
        let compiler = Compiler(frame: try design.accept(frame))
        let compiled = try compiler.compile()
        let names = compiled.simulationObjects.map { $0.name }
            .sorted()
        
        XCTAssertEqual(names, ["a"])
    }

    func testValidateDuplicateName() throws {
        let c1 = frame.createNode(ObjectType.Stock,
                                  name: "things",
                                  attributes: ["formula": "0"])
        let c2 = frame.createNode(ObjectType.Stock,
                                  name: "things",
                                  attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock,
                         name: "a",
                         attributes: ["formula": "0"])
        frame.createNode(ObjectType.Stock,
                         name: "b",
                         attributes: ["formula": "0"])

        // TODO: Check using violation checker
        
        let compiler = Compiler(frame: try design.accept(frame))
        XCTAssertThrowsError(try compiler.compile()) {
            guard $0 as? CompilerError != nil else {
                XCTFail("Expected DomainError, got: \($0)")
                return
            }
            XCTAssertEqual(compiler.issues(for: c1).count, 1)
            XCTAssertEqual(compiler.issues(for: c2).count, 1)
        }
    }

    
    func testInflowOutflow() throws {
        let source = frame.createNode(ObjectType.Stock,
                                      name: "source",
                                      attributes: ["formula": "0"])
        let flow = frame.createNode(ObjectType.Flow,
                                    name: "f",
                                    attributes: ["formula": "1"])
        let sink = frame.createNode(ObjectType.Stock,
                                    name: "sink",
                                    attributes: ["formula": "0"])

        frame.createEdge(ObjectType.Drains,
                         origin: source,
                         target: flow,
                         components: [])
        frame.createEdge(ObjectType.Fills,
                         origin: flow,
                         target: sink,
                         components: [])
        
        let compiler = Compiler(frame: try design.accept(frame))
        let compiled = try compiler.compile()
        
        XCTAssertEqual(compiled.stocks.count, 2)
        XCTAssertEqual(compiled.stocks[0].id, source)
        XCTAssertEqual(compiled.stocks[0].inflows, [])
        XCTAssertEqual(compiled.stocks[0].outflows,
                       [compiled.variableIndex(of: flow)])

        XCTAssertEqual(compiled.stocks[1].id, sink)
        XCTAssertEqual(compiled.stocks[1].inflows,
                       [compiled.variableIndex(of: flow)])
        XCTAssertEqual(compiled.stocks[1].outflows, [])
    }
    
    
    func testDisconnectedGraphicalFunction() throws {
        let gf = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g")

        let compiler = Compiler(frame: try design.accept(frame))
        XCTAssertThrowsError(try compiler.compile()) {
            guard $0 as? CompilerError != nil else {
                XCTFail("Expected DomainError, got: \($0)")
                return
            }
            let issues = compiler.issues(for: gf)
            
            XCTAssertEqual(issues.count, 1)
            XCTAssertEqual(issues.first, NodeIssue.missingRequiredParameter)
            
        }
    }

    func testGraphicalFunctionNameReferences() throws {
        let param = frame.createNode(ObjectType.Auxiliary,
                                  name: "p",
                                     attributes: ["formula": "1"])
        let gf = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g")
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name:"a",
                                   attributes: ["formula": "g"])

        frame.createEdge(ObjectType.Parameter, origin: param, target: gf)
        frame.createEdge(ObjectType.Parameter, origin: gf, target: aux)

        let compiler = Compiler(frame: try design.accept(frame))
        let compiled = try compiler.compile()

        let funcs = compiled.graphicalFunctions
        XCTAssertEqual(funcs.count, 1)

        let boundFn = funcs.first!
        XCTAssertEqual(boundFn.id, gf)
        XCTAssertEqual(boundFn.parameterIndex,
                       compiled.variableIndex(of:param))

        XCTAssertTrue(compiled.simulationObjects.contains { $0.name == "g" })
        
        let issues = compiler.validateParameters(aux, required: ["g"])
        XCTAssertTrue(issues.isEmpty)
    }


    func testGraphicalFunctionComputation() throws {
        let p = frame.createNode(ObjectType.Auxiliary,
                                   name:"p",
                                 attributes: ["formula": "0"])

        let gf = frame.createNode(ObjectType.GraphicalFunction,
                                  name: "g")
        let aux = frame.createNode(ObjectType.Auxiliary,
                                   name:"a",
                                   attributes: ["formula": "g"])

        frame.createEdge(ObjectType.Parameter, origin: p, target: gf)
        frame.createEdge(ObjectType.Parameter, origin: gf, target: aux)

        let compiler = Compiler(frame: try design.accept(frame))
        let compiled = try compiler.compile()
        guard let object = compiled.simulationObject(gf) else {
            XCTFail("No compiled variable for the graphical function")
            return
        }

        switch object.computation {
        case .graphicalFunction(let fn, _):
            XCTAssertEqual(fn.name, "__graphical_\(gf)")
        default:
            XCTFail("Graphical function compiled as: \(object.computation)")
        }
    }

    func testGraphCycleError() throws {
        let a = frame.createNode(ObjectType.Auxiliary,
                                 name:"a",
                                 attributes: ["formula": "b"])
        let b = frame.createNode(ObjectType.Auxiliary,
                                 name:"b",
                                 attributes: ["formula": "a"])
        frame.createEdge(ObjectType.Parameter, origin: a, target: b)
        frame.createEdge(ObjectType.Parameter, origin: b, target: a)
        let compiler = Compiler(frame: try design.accept(frame))
        XCTAssertThrowsError(try compiler.compile()) {
            guard $0 as? CompilerError != nil else {
                XCTFail("Expected CompilerError, got: \($0)")
                return
            }
            
            XCTAssertEqual(compiler.issues(for: a).first, NodeIssue.computationCycle)
            XCTAssertEqual(compiler.issues(for: b).first, NodeIssue.computationCycle)
        }
    }
    
    func testStockCycleError() throws {
        let a = frame.createNode(ObjectType.Stock,
                                 name:"a",
                                 attributes: ["formula": "0"])
        let b = frame.createNode(ObjectType.Stock,
                                 name:"b",
                                 attributes: ["formula": "0"])
        let fab = frame.createNode(ObjectType.Flow,
                                   name: "fab",
                                   attributes: ["formula": "0"])
        let fba = frame.createNode(ObjectType.Flow,
                                   name: "fba",
                                   attributes: ["formula": "0"])
        frame.createEdge(ObjectType.Drains, origin: a, target: fab)
        frame.createEdge(ObjectType.Fills, origin: fab, target: b)
        frame.createEdge(ObjectType.Drains, origin: b, target: fba)
        frame.createEdge(ObjectType.Fills, origin: fba, target: a)

        let compiler = Compiler(frame: try design.accept(frame))
        XCTAssertThrowsError(try compiler.compile()) {
            guard $0 as? CompilerError != nil else {
                XCTFail("Expected CompilerError, got: \($0)")
                return
            }
            
            XCTAssertEqual(compiler.issues(for: a).first, NodeIssue.flowCycle)
            XCTAssertEqual(compiler.issues(for: b).first, NodeIssue.flowCycle)
        }
    }
    func testDelayedInflowBreaksTheCycle() throws {
        let a = frame.createNode(ObjectType.Stock,
                                 name:"a",
                                 attributes: [
                                    "formula": "0",
                                    "delayed_inflow": Variant(true)
                                 ])
        let b = frame.createNode(ObjectType.Stock,
                                 name:"b",
                                 attributes: ["formula": "0"])
        let fab = frame.createNode(ObjectType.Flow,
                                   name: "fab",
                                   attributes: ["formula": "0"])
        let fba = frame.createNode(ObjectType.Flow,
                                   name: "fba",
                                   attributes: ["formula": "0"])
        frame.createEdge(ObjectType.Drains, origin: a, target: fab)
        frame.createEdge(ObjectType.Fills, origin: fab, target: b)
        frame.createEdge(ObjectType.Drains, origin: b, target: fba)
        frame.createEdge(ObjectType.Fills, origin: fba, target: a)

        let compiler = Compiler(frame: try design.accept(frame))
        XCTAssertNoThrow(try compiler.compile())
    }

}
