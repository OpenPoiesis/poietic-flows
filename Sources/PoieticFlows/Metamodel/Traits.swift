//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 23/02/2024.
//

import PoieticCore

extension Trait {
    
    public static let ComputedValue = Trait(
        name: "ComputedValue",
        attributes: [],
        abstract: "Trait for nodes that have a computed value"
    )

    // TODO: Rename to display_value_* pattern and then min/max/baseline
    // TODO: Consider renaming to "TimeSeries" or just "NumericValue"
    
    public static let NumericIndicator = Trait(
        name: "NumericIndicator",
        attributes: [
            Attribute("indicator_min_value", type: .double, optional: true,
                      abstract: "Typically expected minimum value"),
            Attribute("indicator_max_value", type: .double, optional: true,
                      abstract: "Typically expected maxim value"),
            Attribute("indicator_mid_value", type: .double, optional: true,
                      abstract: "Typically expected middle value for differentiating positive and negative relative to the mid-value"),
            Attribute("display_value_auto_scale", type: .bool, optional: true,
                      abstract: "Scale the min/max display value bounds based on the data"),
        ],
        abstract: "Trait for objects that might have a visual numeric indicator"
    )


    public static let Auxiliary = Trait(
        name: "Auxiliary",
        attributes: [],
        abstract: "Abstract trait for auxiliary nodes"
    )

    /// Trait of nodes representing a stock.
    ///
    /// Analogous concept to a stock is an accumulator, container, reservoir
    /// or a pool.
    ///
    public static let Reservoir = Trait(
        name: "Reservoir",
        attributes: [
            Attribute("allows_negative", type: .bool,
                      default: Variant(false),
                      abstract: "Flag whether the stock can contain a negative value"
                     ),
        ]
    )
    // TODO: Remove this in favour of Reservoir
    public static let Stock = Trait(
        name: "Stock",
        attributes: [ /* No attributes for abstract stock */ ]
    )

    /// Trait of nodes representing a flow rate valve.
    ///
    /// Flow is a node that can be connected to two stocks by a flow edge.
    /// One stock is an inflow - stock from which the node drains,
    /// and another stock is an outflow - stock to which the node fills.
    ///
    /// - Note: Current implementation considers are flows to be one-directional
    ///         flows. Flow with negative value, which is in fact an outflow,
    ///         will be ignored.
    ///
    public static let FlowRate = Trait(
        name: "FlowRate",
        attributes: [
            /// Priority specifies an order in which the flow will be considered
            /// when draining a non-negative stocks. The lower the number, the higher
            /// the priority.
            ///
            /// - Note: It is highly recommended to specify priority explicitly if a
            /// functionality that considers the priority is used. It is not advised
            /// to rely on the default priority.
            ///
            Attribute("priority", type: .int, default: Variant(0),
                      abstract: "Priority during computation. The flows are considered in the ascending order of priority."),
        ]
    )
    
    /// Trait of a node representing a graphical function.
    ///
    /// Graphical function is a function defined by its points and an
    /// interpolation method that is used to compute values between the points.
    ///
    public static let GraphicalFunction = Trait(
        name: "GraphicalFunction",
        attributes: [
            Attribute("interpolation_method", type: .string, default: "step",
                      abstract: "Method of interpolation for values between the points"),
            Attribute("graphical_function_points", type: .points,
                      default: Variant(Array<Point>()),
                      abstract: "Points of the graphical function"),
        ],
        abstract: "Function represented by a set of points and an interpolation method."
    )
    
    public static let Delay = Trait(
        name: "Delay",
        attributes: [
            Attribute("delay_duration", type: .double, default: Variant(1),
                      abstract: "Delay duration in steps (time units)"),
        ]
    )

    public static let Smooth = Trait(
        name: "Smooth",
        attributes: [
            Attribute("window_time", type: .double,
                      abstract: "Averaging window time"),
        ]
    )

    
    /// Trait of a node that represents a chart.
    ///
    public static let Chart = Trait(
        name: "Chart",
        attributes: [
            Attribute("min_x_value", type: .numeric, optional: true, abstract: "Minimum value"),
            Attribute("max_x_value", type: .numeric, optional: true, abstract: "Maximum value"),
            Attribute("major_x_steps", type: .numeric, optional: true, abstract: "Major marks and grid steps"),
            Attribute("minor_x_steps", type: .numeric, optional: true, abstract: "Minor marks and grid steps"),
            Attribute("min_y_value", type: .numeric, optional: true, abstract: "Minimum value"),
            Attribute("max_y_value", type: .numeric, optional: true, abstract: "Maximum value"),
            Attribute("major_y_steps", type: .numeric, optional: true, abstract: "Major marks and grid steps"),
            Attribute("minor_y_steps", type: .numeric, optional: true, abstract: "Minor marks and grid steps"),
        ]
    )

    public static let ChartSeries = Trait(
        name: "ChartSeries",
        attributes: [
            Attribute("color", type: .string, optional: true, abstract: "Colour name from the palette of colours"),
        ]
    )

    public static let Control = Trait(
        name: "Control",
        attributes: [
            Attribute("value",
                      type: .double,
                      default: Variant(0.0),
                      abstract: "Value of the target node"),
            Attribute("control_type",
                      type: .string,
                      optional: true,
                      abstract: "Visual type of the control"),
            Attribute("min_value",
                      type: .double,
                      optional: true,
                      abstract: "Minimum possible value of the target variable"),
            Attribute("max_value",
                      type: .double,
                      optional: true,
                      abstract: "Maximum possible value of the target variable"),
            Attribute("step_value",
                      type: .double,
                      optional: true,
                      abstract: "Step for a slider control"),
            // TODO: numeric (default), percent, currency
            Attribute("value_format",
                      type: .string,
                      optional: true,
                      abstract: "Display format of the value"),

        ]
    )

    /// Trait with simulation defaults.
    ///
    /// This trait is used to specify default values of a simulation such as
    /// initial time or time delta in the model. Users usually override
    /// these values in an application performing the simulation.
    ///
    /// Attributes:
    ///
    /// - `initial_time` (double) – initial time of the simulation, default is
    ///    0.0 as most commonly used value
    /// - `time_delta` (double) – time delta, default is 1.0 as most commonly
    ///   used value
    /// - `steps` (int) – default number of simulation steps, default is 10
    ///    (arbitrary, low number just enough to demonstrate something)
    ///
    public static let Simulation = Trait(
        name: "Simulation",
        attributes: [
            Attribute("initial_time", type: .double,
                      default: Variant(0.0),
                      optional: true,
                      abstract: "Initial simulation time"
                     ),
            Attribute("time_delta", type: .double,
                      default: Variant(1.0),
                      optional: true,
                      abstract: "Advancement of time for each simulation step"
                     ),
            Attribute("end_time", type: .double,
                      default: Variant(10.0),
                      optional: true,
                      abstract: "Final simulation time"
                     ),
            Attribute("steps", type: .int,
                      optional: true,
                      abstract: "Number of steps the simulation is run by default [deprecated]"
                     ),
            // TODO: Add stop_time or final_time
            // TODO: Support date/time
            // TODO: Add Solver type
        ]
    )
}
