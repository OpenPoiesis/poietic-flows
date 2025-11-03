//
//  PresentationSystems.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore


public struct ChartComponent: Component {
    struct Series {
        var colorName: String?
    }
    
    /// Chart-type node.
    ///
    /// Series are connected from the node through a `Series` edge, where the chart is the
    /// edge origin and the series node is the edge target.
    ///
    public let chartObject: ObjectSnapshot
    
//    let minX: Double?
//    let maxX: Double?
//    let minY: Double?
//    let maxY: Double?
//    let majorXSteps: Double?
//    let minorXSteps: Double?
//    let majorYSteps: Double?
//    let minorYSteps: Double?
    
    /// Nodes that represent the chart series.
    ///
    /// Series are connected from the node through a `Series` edge, where the chart is the
    /// edge origin and the series node is the edge target.
    ///
    public let series: [ObjectSnapshot]
}

/// System that collects all flow rates and determines their inflows and outflows.
///
/// - **Input:** Nodes of type ``ObjectType/Chart``,
/// - **Output:** Set ``ChartsComponent`` for each chart node.
/// - **Forgiveness:** If multiple ``ObjectType/Flow`` edges exist, only one is picked arbitrarily.
///
public struct ChartResolutionSystem: System {
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
