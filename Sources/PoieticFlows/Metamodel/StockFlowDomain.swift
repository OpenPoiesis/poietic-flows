//
//  StockFlowDomain.swift
//
//
//  Created by Stefan Urbanek on 06/06/2023.
//

import PoieticCore

public enum StockFlowDomain {
    public enum Traits {
        public static let ComputedValue = Trait(
            name: "ComputedValue",
            attributes: [],
            abstract: "Trait for nodes that have a computed value"
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
                /// - Note: No longer used by the simulation.
                ///
                Attribute("priority", type: .int, default: Variant(0),
                          abstract: "Priority during computation. (no longer used)"),
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
        /// - `solver_type` (string) – solver used for integration: `euler` or `rk4`
        /// - `flow_scaling` (string) – `inflow_first`, `outflow_first`
        ///
        public static let StockFlowSimulationSettings = Trait(
            // TODO: Split to SimulationTime and SimulationConfiguration
            name: "StockFlowSimulationSettings",
            attributes: [
                Attribute("solver_type", type: .string, optional: true, abstract: "Solver type name"),
                Attribute("flow_scaling", type: .string, optional: true, abstract: "Flow scaling method"),
            ]
        )
    }
    
    public enum Types {
        /// A stock node - one of the two core nodes.
        ///
        /// Stock node represents a pool, accumulator, a stored value.
        ///
        /// Stock can be connected to many flows that drain or fill the stock.
        ///
        /// - SeeAlso: ``ObjectType/Flow``.
        ///
        public static let Stock = ObjectType(
            // FIXME: Rename to "Reservoir" and make it conform to "Stock"
            name: "Stock",
            topologyType: .node,
            traits: [
                BasicDomain.Traits.Name,
                DiagramDomain.Traits.AccentColor,
                SimulationDomain.Traits.Formula,
                Traits.Stock,
                Traits.Reservoir,
                Traits.ComputedValue,
                SimulationDomain.Traits.NumericValue,
                DiagramDomain.Traits.DiagramBlock,
            ],
            secondaryLabelAttribute: "formula"
        )
        
        /// A flow rate node.
        ///
        /// Flow rate node represents a rate at which a stock is drained or a stock
        /// is filed.
        ///
        /// Flow can be connected to only one stock that the flow fills and from
        /// only one stock that the flow drains.
        ///
        /// ```
        ///                    drains           fills
        ///     Stock source ----------> Flow ---------> Stock drain
        ///
        /// ```
        ///
        /// - SeeAlso: Object types ``Stock`` (node), ``Flow`` (edge).
        ///
        public static let FlowRate = ObjectType(
            name: "FlowRate",
            topologyType: .node,
            traits: [
                BasicDomain.Traits.Name,
                DiagramDomain.Traits.AccentColor,
                SimulationDomain.Traits.Formula,
                Traits.FlowRate,
                Traits.ComputedValue,
                SimulationDomain.Traits.NumericValue,
                DiagramDomain.Traits.DiagramBlock,
            ],
            secondaryLabelAttribute: "formula"
        )
        
        /// An auxiliary node - containing a constant or a formula.
        ///
        public static let Auxiliary = ObjectType(
            name: "Auxiliary",
            topologyType: .node,
            traits: [
                Traits.Auxiliary,
                BasicDomain.Traits.Name,
                DiagramDomain.Traits.AccentColor,
                SimulationDomain.Traits.Formula,
                Traits.ComputedValue,
                SimulationDomain.Traits.NumericValue,
                DiagramDomain.Traits.DiagramBlock,
            ],
            secondaryLabelAttribute: "formula"
        )
        
        /// A cloud node representing out-of-scope stock that has no restrictions.
        ///
        /// - SeeAlso: ``ObjectType/Stock``.
        ///
        public static let Cloud = ObjectType(
            name: "Cloud",
            topologyType: .node,
            traits: [
                Traits.Stock,
                DiagramDomain.Traits.DiagramBlock,
            ],
            labelAttribute: nil, // default is "name", we do not want that
        )
        
        /// An auxiliary node with a function that is described by a graph.
        ///
        /// Graphical function is specified by a collection of 2D points.
        ///
        public static let GraphicalFunction = ObjectType(
            name: "GraphicalFunction",
            topologyType: .node,
            traits: [
                Traits.Auxiliary,
                DiagramDomain.Traits.AccentColor,
                BasicDomain.Traits.Name,
                DiagramDomain.Traits.DiagramBlock,
                Traits.GraphicalFunction,
                Traits.ComputedValue,
                SimulationDomain.Traits.NumericValue
            ]
        )
        
        /// Delay node - delays the input by a given number of steps.
        ///
        public static let Delay = ObjectType(
            name: "Delay",
            topologyType: .node,
            traits: [
                Traits.Auxiliary,
                DiagramDomain.Traits.AccentColor,
                BasicDomain.Traits.Name,
                DiagramDomain.Traits.DiagramBlock,
                Traits.ComputedValue,
                SimulationDomain.Traits.NumericValue,
                Traits.Delay,
            ],
            secondaryLabelAttribute: "delay_duration",
        )
        
        /// Exponential smoothing.
        ///
        public static let Smooth = ObjectType(
            name: "Smooth",
            topologyType: .node,
            traits: [
                DiagramDomain.Traits.AccentColor,
                Traits.ComputedValue,
                Traits.Auxiliary,
                BasicDomain.Traits.Name,
                DiagramDomain.Traits.DiagramBlock,
                SimulationDomain.Traits.NumericValue,
                Traits.Smooth,
            ],
            secondaryLabelAttribute: "window_time",
        )
        
        /// A user interface mode representing a control that modifies a value of
        /// its target node.
        ///
        /// For control node to work, it should be connected to its target node with
        /// `ValueBinding` edge.
        ///
        public static let Control = ObjectType(
            name: "Control",
            topologyType: .node,
            traits: [
                BasicDomain.Traits.Name,
                Traits.Control,
            ]
        )
        
        /// A user interface node representing a chart.
        ///
        /// Chart contains series that are connected with the chart using the
        /// ``ChartSeries`` edge where the origin is the chart and
        /// the target is a value node.
        ///
        public static let Chart = ObjectType(
            name: "Chart",
            topologyType: .node,
            traits: [
                BasicDomain.Traits.Orderable,
                Traits.Chart,
            ]
        )
        
        /// A node that contains a note, a comment.
        ///
        /// The note is not used for simulation, it exists solely for the purpose
        /// to provide user-facing information.
        ///
        public static let Note = ObjectType(
            name: "Note",
            topologyType: .node,
            traits: [
                DiagramDomain.Traits.DiagramBlock,
                BasicDomain.Traits.Note,
            ]
        )
        
        public static let Comment = ObjectType(
            name: "Comment",
            topologyType: .edge,
            traits: [
                DiagramDomain.Traits.DiagramConnector
            ]
        )
        
        /// An edge between stock node and a flow rate node.
        ///
        /// Origin stock of the edge is drained, target stock is being filled. One end
        /// of the edge must be a stock and another edge must be a flow.
        ///
        /// - SeeAlso: ``FlowRate``
        ///
        public static let Flow = ObjectType(
            name: "Flow",
            topologyType: .edge,
            traits: [
                DiagramDomain.Traits.DiagramConnector
            ],
            abstract: "Edge between a stock node and a flow rate node"
        )
        
        /// An edge between a node that serves as a parameter in another node.
        ///
        /// For example, if a flow has a formula `rate * 10` then the node
        /// with name `rate` is connected to the flow through the parameter edge.
        ///
        public static let Parameter = ObjectType(
            name: "Parameter",
            topologyType: .edge,
            traits: [
                DiagramDomain.Traits.DiagramConnector
            ]
        )
        
        /// An edge type to connect controls with their targets.
        ///
        /// The origin of the node is a control – ``Control``, the
        /// target is a node representing a value.
        ///
        public static let ValueBinding = ObjectType(
            name: "ValueBinding",
            topologyType: .edge,
            traits: [
                // None for now
            ],
            abstract: "Edge between a control and a value node. The control observes the value after each step."
        )
        
        /// An edge type to connect a chart with a series that are included in the
        /// chart.
        ///
        /// The origin of the node is a chart – ``Chart`` and
        /// the target of the node is a node representing a value.
        ///
        public static let ChartSeries = ObjectType(
            name: "ChartSeries",
            topologyType: .edge,
            traits: [
                BasicDomain.Traits.Orderable,
                Traits.ChartSeries,
            ],
            abstract: "Edge between a chart and an object with time series"
        )
        // ---------------------------------------------------------------------
        
        // Scenario
        
        public static let Scenario = ObjectType(
            name: "Scenario",
            topologyType: .node,
            traits: [
                SimulationDomain.Traits.Scenario,
                BasicDomain.Traits.Name,
                BasicDomain.Traits.Documentation,
                BasicDomain.Traits.Orderable,
            ]
            
            // Outgoing edges: ValueBinding with attribute "value"
        )
        
        public static let Simulation = ObjectType (
            name: "Simulation",
            topologyType: .unstructured,
            traits: [
                //            Trait.Scenario,
                SimulationDomain.Traits.SimulationTime,
                Traits.StockFlowSimulationSettings,
            ]
        )
    }
    
    
    
    /// The metamodel for Stock-and-Flows domain model.
    ///
    /// The `FlowsMetamodel` describes concepts, components, constraints and
    /// queries that define the [Stock and Flow](https://en.wikipedia.org/wiki/Stock_and_flow)
    /// model domain.
    ///
    /// The basic object types are: `Stock`, `Flow`, `Auxiliary`. More advanced
    /// node type is `GraphicalFunction`.
    ///
    /// - SeeAlso: `Metamodel` protocol description for more information and reasons
    /// behind this approach of describing the metamodel.
    ///
    public static let StockFlowBaseMetamodel = Metamodel(
        name: "StockFlow",
        /// List of components that are used in the Stock and Flow models.
        ///
        traits: [
            BasicDomain.Traits.Name,
            Traits.StockFlowSimulationSettings,
            SimulationDomain.Traits.Scenario,
            // Tags
            Traits.ComputedValue,
            SimulationDomain.Traits.NumericValue,
            
            // Visual
            DiagramDomain.Traits.DiagramBlock,
            DiagramDomain.Traits.DiagramConnector,
            DiagramDomain.Traits.AccentColor,
            
            // Basic Stock-Flow nodes
            Traits.Stock,
            Traits.Auxiliary,
            Traits.Reservoir,
            Traits.FlowRate,
            SimulationDomain.Traits.Formula,
            Traits.GraphicalFunction,
            Traits.Delay,
            Traits.Smooth,
            
            // Others
            Traits.Chart,
            Traits.ChartSeries,
            Traits.Control,
            SimulationDomain.Traits.SimulationTime,
            BasicDomain.Traits.BibliographicalReference,
            BasicDomain.Traits.Orderable,
            BasicDomain.Traits.Note,
        ],
        
        // NOTE: If we were able to use Mirror on types, we would not need this
        /// List of object types for the Stock and Flow metamodel.
        ///
        types: [
            // Nodes
            Types.Stock,
            Types.Cloud,
            Types.FlowRate,
            Types.Auxiliary,
            Types.GraphicalFunction,
            Types.Delay,
            Types.Smooth,
            
            // Edges
            Types.Flow,
            Types.Parameter,
            
            // UI
            Types.Control,
            Types.Chart,
            Types.ChartSeries,
            Types.ValueBinding,
            
            // Other
            Types.Simulation,
            BasicDomain.Types.BibliographicalReference,
            Types.Note,
        ],
        
        // MARK: Edge Rules
        // --------------------------------------------------------------------
        /**
         edge       origin  target    origin outgoing    target incoming
         ---
         parameter  aux     aux         many    many
         parameter  resv.   aux         many    many
         parameter  flow    aux         many    many
         
         parameter  aux     flow        many    many
         parameter  flow    flow        many    many
         parameter  resv.   flow        many    many
         
         parameter  aux     gr func     many    one
         parameter  resv.   gr func     many    one
         parameter  flow    gr func     many    one
         flow       stock   flow        many    one
         flow       flow    stock       one    many
         flow       cloud   flow        many    one
         flow       flow    stock       one    many
         comment    any     any         many    many
         */
        
        /// List of rules describing which edges are valid and what are their requirements.
        ///
        edgeRules: [
            EdgeRule(type: Types.Flow,
                     origin: .isType(Types.FlowRate),
                     outgoing: .one,
                     target: .hasTrait(Traits.Stock)),
            EdgeRule(type: Types.Flow,
                     origin: .hasTrait(Traits.Stock),
                     target: .isType(Types.FlowRate),
                     incoming: .one),
            EdgeRule(type: Types.Parameter,
                     origin: .hasTrait(Traits.Auxiliary)
                .or(.isType(Types.Stock))
                .or(.isType(Types.FlowRate)),
                     outgoing: .many,
                     target: .isType(Types.GraphicalFunction),
                     incoming: .one),
            EdgeRule(type: Types.Parameter,
                     origin: .hasTrait(Traits.Auxiliary)
                .or(.isType(Types.Stock))
                .or(.isType(Types.FlowRate)),
                     outgoing: .many,
                     target: .hasTrait(Traits.Auxiliary)
                .or(.isType(Types.Stock))
                .or(.isType(Types.FlowRate)),
                     incoming: .many),
            EdgeRule(type: Types.Comment,
                     outgoing: .many,
                     incoming: .many),
            
            // Control
            EdgeRule(type: Types.ValueBinding,
                     origin: .isType(Types.Control),
                     target: .hasTrait(SimulationDomain.Traits.Formula)),
            
            // Charts
            EdgeRule(type: Types.ChartSeries,
                     origin: .isType(Types.Chart),
                     target: .hasTrait(Traits.ComputedValue)),
        ]
    )
 
    public static let StockFlowMetamodel = Metamodel(
        name: "StockFlow",
        merging: BasicDomain.BasicMetamodel, StockFlowBaseMetamodel
    )
}
