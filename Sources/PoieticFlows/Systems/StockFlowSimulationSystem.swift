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
/// - **Input:** ``SimulationPlan`` singleton – required. Optional ``SimulationSettings``
///             singleton and ``ScenarioParameters`` singleton.
/// - **Output:** ``SimulationResult`` singleton.
/// - **Forgiveness:** Nothing is proposed if the plan is missing.
/// - **Issues:** No issues created.
///
public class StockFlowSimulationSystem: System {
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(SimulationPlanningSystem.self),
    ]
    public required init() {}
    public func update(_ world: World) throws (InternalSystemError) {
        guard let plan: SimulationPlan = world.singleton() else { return }
        let settings: SimulationSettings = world.singleton() ?? SimulationSettings()
        let params: ScenarioParameters = world.singleton() ?? ScenarioParameters()
        guard let solverType = StockFlowSimulation.SolverType(rawValue: settings.solverType) else {
            throw InternalSystemError(self, message: "Unknown solver type: \(settings.solverType)")
        }

        let simulation = StockFlowSimulation(plan, solver: solverType)

        var result = SimulationResult(initialTime: settings.initialTime,
                                      timeDelta: settings.timeDelta)

        var currentState = try initialize(world: world,
                                          plan: plan,
                                          settings: settings,
                                          parameters: params)
        // TODO: Trigger event "simulation initialised"
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

        // TODO: Trigger event "simulation finished"

        world.setSingleton(result)
    }
    
    public func initialize(world: World,
                           plan: SimulationPlan,
                           settings: SimulationSettings,
                           parameters: ScenarioParameters)
    throws (InternalSystemError) -> SimulationState
    {
        guard let solverType = StockFlowSimulation.SolverType(rawValue: settings.solverType) else {
            throw InternalSystemError(self, message: "Unknown solver type: \(settings.solverType)")
        }
        // TODO: Add flow scaling parameter
        let simulation = StockFlowSimulation(plan, solver: solverType)

        let state: SimulationState
        do {
            state = try simulation.initialize(time: settings.initialTime,
                                              timeDelta: settings.timeDelta,
                                              parameters: parameters.initialValues)
        }
        catch {
            // FIXME: Handle this error with a simulation result/error component.
            throw InternalSystemError(self, message: "Unhandled simulation error: \(error)")
        }
        return state
    }
    
    public func step(simulation: StockFlowSimulation,
                     state currentState: SimulationState)
    throws (InternalSystemError) -> SimulationState {
        let newState: SimulationState
        do {
            newState = try simulation.step(currentState)
        }
        catch {
            throw InternalSystemError(self, message: "Unhandled simulation error: \(error)")
        }

        return newState
    }

}
