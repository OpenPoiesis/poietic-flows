//
//  FlowsSystemCollections.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

import PoieticCore

/// Systems required to be run for creating a simulation plan.
///
nonisolated(unsafe) public let SimulationPlanningSystems: [System.Type] = [
    ExpressionParserSystem.self,
    ParameterResolutionSystem.self,
    ComputationOrderSystem.self,
    NameResolutionSystem.self,
    StockFlowTopologySystem.self,
    SimulationPlanningSystem.self,
    SimulationSettingsSystem.self,
]

nonisolated(unsafe) public let SimulationRunningSystems: [System.Type] = [
    StockFlowSimulationSystem.self,
]
