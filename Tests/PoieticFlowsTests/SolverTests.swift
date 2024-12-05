//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 08/06/2023.
//

import XCTest
@testable import PoieticFlows
@testable import PoieticCore

final class TestSimulator: XCTestCase {
    var design: Design!
    var frame: TransientFrame!
    
    override func setUp() {
        design = Design(metamodel: FlowsMetamodel)
        frame = design.createFrame()
    }
    
    func compile() throws -> SimulationPlan {
        let compiler = Compiler(frame: try design.accept(frame))
        return try compiler.compile()
    }
    
    func testTime() throws {
        let compiled = try compile()
        let timeIndex = compiled.timeVariableIndex

        let simulator = Simulator(compiled)

        let state = try simulator.initializeState(time: 10.0)
        XCTAssertEqual(state[timeIndex], 10.0)
    }
}
