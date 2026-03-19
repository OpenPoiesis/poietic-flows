//
//  Chart.swift
//
//
//  Created by Stefan Urbanek on 11/09/2023.
//

import PoieticCore

/// Component representing a chart.
///
/// Created for design objects of type `Chart`.
///
/// Chart design object have outgoing edges of type `ChartSeries` which will be spawned as
/// entities with ``ChartSeries`` component.
///
public struct Chart: Component {
    public struct Axis {
        public let displayBounds: DisplayValueBounds
        public let majorSteps: Double?
        public let minorSteps: Double?
    }
    
    public let xAxis: Axis
    public let yAxis: Axis
    
    public init(from object: ObjectSnapshot) {
        xAxis = Axis(
            displayBounds: DisplayValueBounds(
                min: object["min_x_value"],
                max: object["max_x_value"],
                baseline: nil
            ),
            majorSteps: object["major_x_steps"],
            minorSteps: object["minor_x_steps"]
        )
        yAxis = Axis(
            displayBounds: DisplayValueBounds(
                min: object["min_y_value"],
                max: object["max_y_value"],
                baseline: nil
            ),
            majorSteps: object["major_y_steps"],
            minorSteps: object["minor_y_steps"]
        )
    }
}

/// Component for entities representing chart series.
///
/// World structure: chart series are children of ``Chart``. They are created from design objects
/// (edges) of type `ChartSeries`.
///
public struct ChartSeries: Relationship {
    public static var removalPolicy: RemovalPolicy { .removeSelf }
    
    /// Value representable object that the series represent. Should be a simulation object.
    ///
    /// If the chart series is created from a design object - edge, then the target property
    /// is the the edge's target.
    ///
    public var target: RuntimeID
    public var colorKey: AdaptableColorKey?

    /// Display value bounds pulled from the target object.
    public var displayBounds: DisplayValueBounds

    public init(target: RuntimeID, colorKey: AdaptableColorKey? = nil, displayBounds: DisplayValueBounds) {
        self.target = target
        self.colorKey = colorKey
        self.displayBounds = displayBounds
    }
}

@available(*, deprecated, message: "Use Chart:Component and ChartSeries component")
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
    public var name: String? { chartObject.name }
    
    /// Nodes that represent the chart series.
    ///
    /// Series are connected from the node through a `Series` edge, where the chart is the
    /// edge origin and the series node is the edge target.
    ///
    public let series: [ObjectSnapshot]
}
