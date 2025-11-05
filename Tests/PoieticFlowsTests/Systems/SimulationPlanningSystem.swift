//
//  SimulationPlanningSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

//
//  ParameterResolutionSystemTests.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 05/11/2025.
//

import Testing
@testable import PoieticFlows
@testable import PoieticCore

@Suite struct SimulationPlannerSystemTests {
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
   
    // TEST: Failed expression -> tries to compile
    
    func createPlan() throws -> SimulationPlan? {
        fatalError()
        // TODO
        
    }
}
