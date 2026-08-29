//
//  StockFlowSimulationSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 31/12/2025.
//

import PoieticCore

/// System that runs a Stock-Flow simulation and stores results in a ``SimulationResult``
/// singleton.
///
/// The simulation time and solver type is retrieved from the ``SimulationSettings`` component.
/// If the component is not present, then defaults are used
/// (see ``SimulationSettings/init(initialTime:timeDelta:endTime:solverType:)``). The simulation
/// is run whole, from the initial time to the end time.
///
///
/// The system has the following limitations, which might be removed in the future:
///
/// - The simulation is run as a whole, there are no external events triggered on each step.
/// - Only the singleton plan is used - only one simulation can be run per world.
///
/// - **Input:**
///     - ``SimulationPlan`` singleton, required.
///     - ``SimulationSettings`` singleton, optional. If not provided then default settings are used.
///     - ``ScenarioParameters`` singleton, optional.
/// - **Output:** ``SimulationResult`` singleton is set when simulation was finished successfully,
///   otherwise the simulation result will be removed or not set.
/// - **Forgiveness:** No forgiveness.
/// - **Issues:** No issues created.
///
public struct StockFlowSimulationSystem: System {
    public static let dependencies: [SystemDependency] = [
        // Soft dependencies - only relevant if the simulation system ends up in the same schedule.
        .after(SimulationPlanningSystem.self),
        .after(SimulationSettingsSystem.self),
    ]

    public static func update(_ world: World) throws (InternalSystemError) {
        world.removeSingleton(SimulationResult.self)

        guard let plan: SimulationPlan = world.singleton() else { return }
        let settings: SimulationSettings = world.singleton() ?? SimulationSettings()
        let parameters: ScenarioParameters = world.singleton() ?? ScenarioParameters()
        
        guard let solverType = StockFlowSimulation.SolverType(rawValue: settings.solverType) else {
            throw InternalSystemError(self, message: "Unknown solver type: \(settings.solverType)")
        }

        // TODO: Add flow scaling parameter
        let simulation = StockFlowSimulation(plan, solver: solverType)

        var result = SimulationResult(initialTime: settings.initialTime,
                                      timeDelta: settings.timeDelta)

        var currentState: SimulationState
        do {
            currentState = try simulation.initialize(time: settings.initialTime,
                                              timeDelta: settings.timeDelta,
                                              parameters: parameters.values)
        }
        catch {
            // TODO: Consider object issue component, if relevant.
            throw InternalSystemError(self, message: "Simulation failed: \(error)")
        }

        result.append(currentState)
        var currentTime = settings.initialTime
        var step: UInt = 1

        while step <= settings.steps {
            let newState = try self.step(simulation: simulation, state: currentState)
            result.append(newState)
            currentState = newState
            currentTime += settings.timeDelta
            step += 1
        }

        world.setSingleton(result)
    }
    
    public static func step(simulation: StockFlowSimulation,
                     state currentState: SimulationState)
    throws (InternalSystemError) -> SimulationState {
        let newState: SimulationState
        do {
            newState = try simulation.step(currentState)
        }
        catch {
            // TODO: Consider object issue component, if relevant.
            throw InternalSystemError(self, message: "Simulation failed: \(error)")
        }

        return newState
    }

}
