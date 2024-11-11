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
            Trait.Position,
            // Abstract
            Trait.Auxiliary,
            Trait.ComputedValue,

            // Basic Stock-Flow nodes
            Trait.Stock,
            Trait.Flow,
            Trait.Formula,
            Trait.GraphicalFunction,
            Trait.Delay,
            Trait.Smooth,
            
            // Others
            Trait.Chart,
            Trait.Simulation,
            Trait.BibliographicalReference,
        ],
        
        // NOTE: If we were able to use Mirror on types, we would not need this
        /// List of object types for the Stock and Flow metamodel.
        ///
        types: [
            // Nodes
            ObjectType.Stock,
            ObjectType.Flow,
            ObjectType.Auxiliary,
            ObjectType.GraphicalFunction,
            ObjectType.Delay,
            ObjectType.Smooth,

            // Edges
            ObjectType.Drains,
            ObjectType.Fills,
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
        
        // MARK: Constraints
        // TODO: Add tests for violation of each of the constraints
        // --------------------------------------------------------------------
        /// List of constraints of the Stock and Flow metamodel.
        ///
        /// The constraints include:
        ///
        /// - Flow must drain (from) a stock, no other kind of node.
        /// - Flow must fill (into) a stock, no other kind of node.
        ///
        constraints: [
            Constraint(
                name: "flow_fills_is_stock",
                abstract: """
                      Flow must drain (from) a stock, no other kind of node.
                      """,
                match: EdgePredicate(IsTypePredicate(ObjectType.Fills)),
                requirement: AllSatisfy(
                    EdgePredicate(
                        origin: IsTypePredicate(ObjectType.Flow),
                        target: IsTypePredicate(ObjectType.Stock)
                    )
                )
            ),
            
            Constraint(
                name: "flow_drains_is_stock",
                abstract: """
                      Flow must fill (into) a stock, no other kind of node.
                      """,
                match: EdgePredicate(IsTypePredicate(ObjectType.Drains)),
                requirement: AllSatisfy(
                    EdgePredicate(
                        origin: IsTypePredicate(ObjectType.Stock),
                        target: IsTypePredicate(ObjectType.Flow)
                    )
                )
            ),
            
            Constraint(
                name: "graph_func_single_param",
                abstract: """
                      Graphical function must not have more than one incoming parameters.
                      """,
                match: IsTypePredicate(ObjectType.GraphicalFunction),
                requirement: UniqueNeighbourRequirement(
                    NeighborhoodSelector(
                        predicate: IsTypePredicate(ObjectType.Parameter),
                        direction: .incoming
                    ),
                    required: false
                )
            ),
            
            // UI
            // TODO: Make the value binding target to be "Value" type (how?)
            Constraint(
                name: "control_value_binding",
                abstract: """
                      Control binding's origin must be a Control and target must be a formula node.
                      """,
                match: EdgePredicate(IsTypePredicate(ObjectType.ValueBinding)),
                requirement: AllSatisfy(
                    EdgePredicate(
                        origin: IsTypePredicate(ObjectType.Control),
                        target: HasTraitPredicate(Trait.Formula)
                    )
                )
            ),
            Constraint(
                name: "chart_series",
                abstract: """
                      Chart series edge must originate in Chart and end in a computed value node.
                      """,
                match: EdgePredicate(IsTypePredicate(ObjectType.ChartSeries)),
                requirement: AllSatisfy(
                    EdgePredicate(
                        origin: IsTypePredicate(ObjectType.Chart),
                        target: HasTraitPredicate(Trait.ComputedValue)
                    )
                )
            ),
            Constraint(
                name: "control_target_is_aux_or_stock",
                abstract: """
                      Control target must be Auxiliary or a Stock node.
                      """,
                match: EdgePredicate(
                    IsTypePredicate(ObjectType.ValueBinding),
                    origin: IsTypePredicate(ObjectType.Control)
                ),
                requirement: AllSatisfy(
                    EdgePredicate(
                        target: IsTypePredicate(ObjectType.Auxiliary)
                            .or(IsTypePredicate(ObjectType.Stock))
                    )
                )
            ),
        ]
    )
}

public let FlowsMetamodel = Metamodel(name: "Flows",
                                      merging: Metamodel.Basic,
                                               Metamodel.StockFlow)
