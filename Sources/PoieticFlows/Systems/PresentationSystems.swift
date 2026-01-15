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
    
    public init(_ world: World) { }

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
}
