//
//  IntermediateComponents.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 17/08/2026.
//

import PoieticCore

/// Component with a list of simulation objects in order of their computational dependency.
///
/// The computational dependency is determined by flow and parameters edges in the design graph.
///
/// - **Produced by:** ``ComputationOrderSystem``
///
public struct SimulationOrder: IntermediateSingleton {
    internal init(objects: [ObjectSnapshot] = []) {
        self.objects = objects
    }
    
    /// List of simulation objects in order of their computational dependency.
    ///
    let objects: [ObjectSnapshot]
}
