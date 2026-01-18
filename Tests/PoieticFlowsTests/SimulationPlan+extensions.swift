//
//  SimulationPlan+extensions.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 22/12/2025.
//

import PoieticCore
import PoieticFlows

extension SimulationPlan {
    /// Index of a stock in a list of stocks or in a stock difference vector.
    ///
    /// This function is not used during computation. It is provided for
    /// potential inspection, testing and debugging.
    ///
    /// - Precondition: The plan must contain a stock with given ID.
    ///
    func stockIndex(_ id: ObjectID) -> NumericVector.Index {
        guard let index = stocks.firstIndex(where: { $0.objectID == id }) else {
            preconditionFailure("The plan does not contain stock with ID \(id)")
        }
        return index
    }
    func flowIndex(_ id: ObjectID) -> NumericVector.Index {
        guard let index = flows.firstIndex(where: { $0.objectID == id }) else {
            preconditionFailure("The plan does not contain flow with ID \(id)")
        }
        return index
    }
    
    func variableIndex(_ object: some ObjectProtocol) -> SimulationState.Index? {
        // Since this is just for debug purposes, O(n) should be fine, no need
        // for added complexity of the code.
        guard let first = simulationObjects.first(where: {$0.objectID == object.objectID}) else {
            return nil
        }
        return first.variableIndex
    }

}
