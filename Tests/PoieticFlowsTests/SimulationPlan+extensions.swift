//
//  SimulationPlan+extensions.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 22/12/2025.
//

import PoieticCore
import PoieticFlows

extension SimulationPlan {
    /// Variable reference of an object.
    ///
    /// Convenience overload used by tests that have an object (for example a
    /// node returned from `TransientPlane/createNode`) instead of an object ID.
    func variableReference(_ object: some ObjectProtocol) -> VariableReference? {
        return variableReference(object.objectID)
    }
}
