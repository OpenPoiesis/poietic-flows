//
//  FlowsSystemCollections.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

import PoieticCore

/// System list that together produces a ``SimulationPlan``.
///
/// Register it in a schedule and run after a plane change.
///
public let SimulationPlanningSystems: [System.Type] = [
    NameNormalizationSystem.self,
    ExpressionParserSystem.self,
    ParameterResolutionSystem.self,
    ComputationOrderSystem.self,
    NameValidationSystem.self,
    StockFlowTopologySystem.self,
    SimulationPlanningSystem.self,
    SimulationSettingsSystem.self,
]

/// The systems that consume the simulation plan and produce simulation results.
///
public let SimulationRunningSystems: [System.Type] = [
    StockFlowSimulationSystem.self,
]
