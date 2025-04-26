//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 23/02/2024.
//

import PoieticCore

extension ObjectType {
    /// A stock node - one of the two core nodes.
    ///
    /// Stock node represents a pool, accumulator, a stored value.
    ///
    /// Stock can be connected to many flows that drain or fill the stock.
    ///
    /// - SeeAlso: ``ObjectType/Flow``.
    ///
    public static let Stock = ObjectType(
        name: "Stock",
        structuralType: .node,
        traits: [
            Trait.Name,
            Trait.Formula,
            Trait.Stock,
            Trait.ComputedValue,
            Trait.NumericIndicator,
            Trait.DiagramNode,
        ]
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
    /// - SeeAlso: ``ObjectType/Stock``, ``ObjectType/Fills``,
    /// ``ObjectType/Drains``.
    ///
    public static let FlowRate = ObjectType(
        name: "FlowRate",
        structuralType: .node,
        traits: [
            Trait.Name,
            Trait.Formula,
            Trait.FlowRate,
            Trait.ComputedValue,
            Trait.NumericIndicator,
            Trait.DiagramNode,
            // DescriptionComponent.self,
            // ErrorComponent.self,
        ]
    )
    
    /// An auxiliary node - containing a constant or a formula.
    ///
    public static let Auxiliary = ObjectType(
        name: "Auxiliary",
        structuralType: .node,
        traits: [
            Trait.Auxiliary,
            Trait.Name,
            Trait.Formula,
            Trait.ComputedValue,
            Trait.NumericIndicator,
            Trait.DiagramNode,
            // DescriptionComponent.self,
            // ErrorComponent.self,
        ]
    )
    
    /// An auxiliary node with a function that is described by a graph.
    ///
    /// Graphical function is specified by a collection of 2D points.
    ///
    public static let GraphicalFunction = ObjectType(
        name: "GraphicalFunction",
        structuralType: .node,
        traits: [
            Trait.Auxiliary,
            Trait.Name,
            Trait.DiagramNode,
            Trait.GraphicalFunction,
            Trait.ComputedValue,
            Trait.NumericIndicator
            // DescriptionComponent.self,
            // ErrorComponent.self,
            // TODO: IMPORTANT: Make sure we do not have formula component here or handle the type
        ]
    )

    /// Delay node - delays the input by a given number of steps.
    ///
    public static let Delay = ObjectType(
        name: "Delay",
        structuralType: .node,
        traits: [
            Trait.Auxiliary,
            Trait.Name,
            Trait.DiagramNode,
            Trait.ComputedValue,
            Trait.NumericIndicator,
            Trait.Delay,
            // DescriptionComponent.self,
            // ErrorComponent.self,
        ]
    )

    /// Exponential smoothing.
    ///
    public static let Smooth = ObjectType(
        name: "Smooth",
        structuralType: .node,
        traits: [
            Trait.ComputedValue,
            Trait.Auxiliary,
            Trait.Name,
            Trait.DiagramNode,
            Trait.ComputedValue,
            Trait.NumericIndicator,
            Trait.Smooth,
            // DescriptionComponent.self,
            // ErrorComponent.self,
        ]
    )

    /// A user interface mode representing a control that modifies a value of
    /// its target node.
    ///
    /// For control node to work, it should be connected to its target node with
    /// ``/PoieticCore/ObjectType/ValueBinding`` edge.
    ///
    public static let Control = ObjectType(
        name: "Control",
        structuralType: .node,
        traits: [
            Trait.Name,
            Trait.Control,
        ]
    )
    
    /// A user interface node representing a chart.
    ///
    /// Chart contains series that are connected with the chart using the
    /// ``/PoieticCore/ObjectType/ChartSeries`` edge where the origin is the chart and
    /// the target is a value node.
    ///
    public static let Chart = ObjectType(
        name: "Chart",
        structuralType: .node,
        traits: [
            Trait.Name,
            Trait.Chart,
        ]
    )
    
    /// A node that contains a note, a comment.
    ///
    /// The note is not used for simulation, it exists solely for the purpose
    /// to provide user-facing information.
    ///
    public static let Note = ObjectType(
        name: "Note",
        structuralType: .node,
        traits: [
            .DiagramNode,
            .Note,
        ]
    )

    public static let Comment = ObjectType(
        name: "Comment",
        structuralType: .edge,
        traits: [
            .DiagramConnector
        ]
    )
    
    /// An edge between stock node and a flow rate node.
    ///
    /// Origin stock of the edge is drained, target stock is being filled. One end
    /// of the edge must be a stock and another edge must be a flow.
    ///
    /// - SeeAlso: ``/PoieticCore/ObjectType/FlowRate``
    ///
    public static let Flow = ObjectType(
        name: "Flow",
        structuralType: .edge,
        traits: [
            .DiagramConnector
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
        structuralType: .edge,
        traits: [
            .DiagramConnector
        ]
    )
    
    /// An edge type to connect controls with their targets.
    ///
    /// The origin of the node is a control – ``/PoieticCore/ObjectType/Control``, the
    /// target is a node representing a value.
    ///
    public static let ValueBinding = ObjectType(
        name: "ValueBinding",
        structuralType: .edge,
        traits: [
            // None for now
        ],
        abstract: "Edge between a control and a value node. The control observes the value after each step."
    )
    
    /// An edge type to connect a chart with a series that are included in the
    /// chart.
    ///
    /// The origin of the node is a chart – ``/PoieticCore/ObjectType/Chart`` and
    /// the target of the node is a node representing a value.
    ///
    public static let ChartSeries = ObjectType(
        name: "ChartSeries",
        structuralType: .edge,
        traits: [
            Trait.ChartSeries,
        ],
        abstract: "Edge between a chart and an object with time series"
    )
    // ---------------------------------------------------------------------

    // Scenario
    
    public static let Scenario = ObjectType(
        name: "Scenario",
        structuralType: .node,
        traits: [
            Trait.Name,
            Trait.Documentation,
        ]
        
        // Outgoing edges: ValueBinding with attribute "value"
    )
    
    public static let Simulation = ObjectType (
        name: "Simulation",
        structuralType: .unstructured,
        traits: [
            Trait.Simulation,
        ]
    )
}



