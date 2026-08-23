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
        
        public init(displayBounds: DisplayValueBounds, majorSteps: Double? = nil, minorSteps: Double? = nil) {
            self.displayBounds = displayBounds
            self.majorSteps = majorSteps
            self.minorSteps = minorSteps
        }
        
        public init() {
            self.displayBounds = DisplayValueBounds()
            self.majorSteps = nil
            self.minorSteps = nil
        }
    }
    
    public let label: String?
    public let xAxis: Axis
    public let yAxis: Axis
    
    public init() {
        self.label = nil
        self.xAxis = Axis()
        self.yAxis = Axis()
    }
    
    public init(from object: ObjectSnapshot) {
        label = object.name
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
/// Chart series are created from design objects (edges) of type `ChartSeries`
///
/// - **CreatedBy:** ``ChartResolutionSystem``.
/// - **UsedBy:** your application.
///
/// Expected components:
///
/// - `ChildOf` relationship to a ``Chart``
/// - `RepresentationOf` relationship to an object with content to be plotted.
///
public struct ChartSeries: Relationship {
    public static var targetRemovalPolicy: RelationshipRemovalPolicy { .despawn }
    
    public var colorKey: AdaptableColorKey?

    /// Display value bounds pulled from the target object.
    public var displayBounds: DisplayValueBounds

    public init(colorKey: AdaptableColorKey? = nil,
                displayBounds: DisplayValueBounds)
    {
        self.colorKey = colorKey
        self.displayBounds = displayBounds
    }
}
