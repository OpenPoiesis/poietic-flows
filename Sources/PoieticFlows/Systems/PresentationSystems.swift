//
//  PresentationSystems.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore


/// System that collects all flow rates and determines their inflows and outflows.
///
/// - **Input:** Nodes of type ``ObjectType/Chart``,
/// - **Output:** Set ``ChartsComponent`` for each chart node.
/// - **Forgiveness:** If multiple ``ObjectType/Flow`` edges exist, only one is picked arbitrarily.
///
public struct ChartResolutionSystem: System {
    
    public init() {}

    public func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        let nodes = frame.filter { $0.type === ObjectType.Chart }
        
        for node in nodes {
            let edges = frame.edges.filter {
                $0.object.type === ObjectType.ChartSeries
            }
            
            let series = edges.map { $0.targetObject }
            let chart = ChartComponent(chartObject: node,
                                        series: series)
            frame.setComponent(chart, for: node.objectID)
        }
    }
    public func makeChart(_ chart: ObjectSnapshot, frame: RuntimeFrame) -> ChartComponent {
        let edges = frame.outgoing(chart.objectID).filter {
            $0.object.type === ObjectType.ChartSeries
        }
        let series = edges.map { $0.targetObject }
        // Check that:
        // - target is numeric value component (can be presented)
        return ChartComponent(chartObject: chart, series: series)
    }
}
