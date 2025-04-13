//
//  Metamodel.swift
//  
//
//  Created by Stefan Urbanek on 06/06/2023.
//

import PoieticCore


extension Metamodel {
    /// The metamodel for Stock-and-Flows domain model.
    ///
    /// The `FlowsMetamodel` describes concepts, components, constraints and
    /// queries that define the [Stock and Flow](https://en.wikipedia.org/wiki/Stock_and_flow)
    /// model domain.
    ///
    /// The basic object types are: ``/PoieticCore/ObjectType/Stock``, ``ObjectType/Flow``, ``ObjectType/Auxiliary``. More advanced
    /// node type is ``/PoieticCore/ObjectType/GraphicalFunction``.
    ///
    /// - SeeAlso: `Metamodel` protocol description for more information and reasons
    /// behind this approach of describing the metamodel.
    ///
    public static let StockFlow = Metamodel(
        name: "StockFlow",
        /// List of components that are used in the Stock and Flow models.
        ///
        traits: [
            Trait.Name,
            Trait.DiagramNode,
            // Abstract
            Trait.Auxiliary,
            Trait.ComputedValue,
            Trait.DiagramNode,
            Trait.DiagramConnector,
            Trait.NumericIndicator,

            // Basic Stock-Flow nodes
            Trait.Stock,
            Trait.FlowRate,
            Trait.Formula,
            Trait.GraphicalFunction,
            Trait.Delay,
            Trait.Smooth,
            
            // Others
            Trait.Chart,
            Trait.ChartSeries,
            Trait.Control,
            Trait.Simulation,
            Trait.BibliographicalReference,
        ],
        
        // NOTE: If we were able to use Mirror on types, we would not need this
        /// List of object types for the Stock and Flow metamodel.
        ///
        types: [
            // Nodes
            ObjectType.Stock,
            ObjectType.FlowRate,
            ObjectType.Auxiliary,
            ObjectType.GraphicalFunction,
            ObjectType.Delay,
            ObjectType.Smooth,

            // Edges
            ObjectType.Flow,
            ObjectType.Parameter,
            
            // UI
            ObjectType.Control,
            ObjectType.Chart,
            ObjectType.ChartSeries,
            ObjectType.ValueBinding,
            
            // Other
            ObjectType.Simulation,
            ObjectType.BibliographicalReference,
            ObjectType.Note,
        ],
        
        // MARK: Edge Rules
        // --------------------------------------------------------------------
        /**
         edge       origin  target    origin outgoing    target incoming
         ---
         parameter  aux     aux         many    many
         parameter  stock   aux         many    many
         parameter  flow    aux         many    many
         
         parameter  aux     flow        many    many
         parameter  flow    flow        many    many
         parameter  stock   flow        many    many

         parameter  aux     gr func     many    one
         parameter  stock   gr func     many    one
         parameter  flow    gr func     many    one
         flow       stock   flow        many    one
         flow       flow    stock       one    many
         flow       cloud   flow        many    one
         flow       flow    cloud       one    many
         comment    any     any         many    many
         */

        /// List of rules describing which edges are valid and what are their requirements.
        ///
        edgeRules: [
            EdgeRule(type: .Flow,
                     origin: IsTypePredicate(.FlowRate),
                     outgoing: .one,
                     target: IsTypePredicate(.Stock)),
            EdgeRule(type: .Flow,
                     origin: IsTypePredicate(.Stock),
                     target: IsTypePredicate(.FlowRate),
                     incoming: .one),
            EdgeRule(type: .Parameter,
                     origin: HasTraitPredicate(.Auxiliary)
                                .or(IsTypePredicate(.Stock))
                                .or(IsTypePredicate(.FlowRate)),
                     outgoing: .many,
                     target: IsTypePredicate(.GraphicalFunction),
                     incoming: .one),
            EdgeRule(type: .Parameter,
                     origin: HasTraitPredicate(.Auxiliary)
                                .or(IsTypePredicate(.Stock))
                                .or(IsTypePredicate(.FlowRate)),
                     outgoing: .many,
                     target: HasTraitPredicate(.Auxiliary)
                                .or(IsTypePredicate(.Stock))
                                .or(IsTypePredicate(.FlowRate)),
                     incoming: .many),
            EdgeRule(type: .Comment,
                     outgoing: .many,
                     incoming: .many),

            // Control
            EdgeRule(type: .ValueBinding,
                     origin: IsTypePredicate(.Control),
                     target: HasTraitPredicate(.Formula)),

            // Charts
            EdgeRule(type: .ChartSeries,
                     origin: IsTypePredicate(.Chart),
                     target: HasTraitPredicate(.ComputedValue)),
        ]
    )
}

// FIXME: [IMPORTANT] There is confusion between FlowsMetamodel and Metamodel.StockFlow, name one as -base and other as -complete or -user
public let FlowsMetamodel = Metamodel(
    name: "Flows",
    merging: Metamodel.Basic, Metamodel.StockFlow
)
