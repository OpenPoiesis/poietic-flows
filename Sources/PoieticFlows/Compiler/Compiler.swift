//
//  Compiler.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

// FIXME: Remove this file once users of this API are happy

import PoieticCore

/// Systems required to be run for creating a simulation plan.
///
nonisolated(unsafe) public let SimulationPlanningSystems: [System.Type] = [
    ExpressionParserSystem.self,
    ParameterResolutionSystem.self,
    ComputationOrderSystem.self,
    NameResolutionSystem.self,
    FlowCollectorSystem.self,
    StockDependencySystem.self,
    SimulationPlanningSystem.self,
]

nonisolated(unsafe) public let SimulationRunningSystems: [System.Type] = [
    StockFlowSimulationSystem.self,
]

/// Systems used to present the simulation results.
///
/// The systems in this collection are expected to be run after ``SimulationPlanningSystems``.
///
nonisolated(unsafe) public let SimulationPresentationSystems: [System.Type] = [
    ChartResolutionSystem.self,
]

