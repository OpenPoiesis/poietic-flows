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
public struct SimulationOrder: Component, _SystemResult {
    internal init(objects: [ObjectSnapshot] = [], stocks: [ObjectID] = [], flows: [ObjectID] = []) {
        self.objects = objects
        self.stocks = stocks
        self.flows = flows
    }
    
    // TODO: Rename to orderedObjects
    /// List of simulation objects in order of their computational dependency.
    ///
    let objects: [ObjectSnapshot]
    // TODO: Documentation
    // Used also for verification whether we got all right
    /// List of object IDs representing stocks, in order of computational dependency within the
    /// whole graph.
    let stocks: [ObjectID]

    /// List of object IDs representing flows, in order of computational dependency within the
    /// whole graph.
    let flows: [ObjectID]
}
