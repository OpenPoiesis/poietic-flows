//
//  ControlsTests.swift
//  
//
//  Created by Stefan Urbanek on 25/08/2023.
//

import XCTest
@testable import PoieticFlows
@testable import PoieticCore


final class TestControls: XCTestCase {
    var design: Design!
    var frame: TransientFrame!
    var model: SimulationPlan!
    
    override func setUp() {
        design = Design(metamodel: StockFlowMetamodel.self)
        frame = design.createFrame()
    }
    
    func compile() throws {
        guard let frame else {
            XCTFail("No frame to compile")
            return
        }
        let compiler = Compiler(frame: try design.validate(try design.accept(frame)))
        model = try compiler.compile()
    }
    
    func testBinding() throws {
        let a = frame.createNode(ObjectType.Auxiliary, name: "a", attributes: ["formula": "10"])
        let control = frame.createNode(ObjectType.Control, name: "control")
        let _ = frame.createEdge(ObjectType.ValueBinding, origin: control, target: a)
        try compile()
       
        XCTAssertEqual(model.valueBindings.count, 1)
        
        let binding = model.valueBindings[0]
        
        XCTAssertEqual(binding.control, control.id)
        XCTAssertEqual(binding.variableIndex, model.variableIndex(of: a.id))
    }
}
