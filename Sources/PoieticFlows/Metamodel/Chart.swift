//
//  Chart.swift
//
//
//  Created by Stefan Urbanek on 11/09/2023.
//

import PoieticCore

/// Object representing a chart.
///
public struct Chart {
    /// Chart-type node.
    ///
    /// Series are connected from the node through a `Series` edge, where the chart is the
    /// edge origin and the series node is the edge target.
    ///
    public let node: ObjectSnapshot
    
    /// Nodes that represent the chart series.
    ///
    /// Series are connected from the node through a `Series` edge, where the chart is the
    /// edge origin and the series node is the edge target.
    ///
    public let series: [ObjectSnapshot]
    
    /// Create a chart object.
    ///
    public init(node: ObjectSnapshot, series: [ObjectSnapshot]) {
        self.node = node
        self.series = series
    }
}
