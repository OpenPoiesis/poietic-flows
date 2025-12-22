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

    public func update(_ world: World) throws (InternalSystemError) {
        guard let frame = world.frame else { return }
        let chartObjects = frame.filter { $0.type === ObjectType.Chart }

        for chartObject in chartObjects {
            let seriesEdges = frame.outgoing(chartObject.objectID).filter {
                $0.object.type === ObjectType.ChartSeries
            }
            
            let series = seriesEdges.map { $0.targetObject }
            let chart = ChartComponent(chartObject: chartObject, series: series)
            world.setComponent(chart, for: chartObject.objectID)
        }
    }
    public func makeChart(_ chart: ObjectSnapshot, frame: AugmentedFrame) -> ChartComponent {
        let edges = frame.outgoing(chart.objectID).filter {
            $0.object.type === ObjectType.ChartSeries
        }
        let series = edges.map { $0.targetObject }
        // Check that:
        // - target is numeric value component (can be presented)
        return ChartComponent(chartObject: chart, series: series)
    }
}
