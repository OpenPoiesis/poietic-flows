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

        guard settings.timeDelta > 0 else {
            throw InternalSystemError("StockFlowSimulationSystem", message: "Time delta must be > 0")
        }
        guard settings.endTime >= settings.initialTime else {
            throw InternalSystemError("StockFlowSimulationSystem", message: "End time must be greater or equal to start time")
        }

        guard let solverType = StockFlowSimulation.SolverType(settings.solverType) else {
            throw InternalSystemError(self, message: "Unknown solver type: \(settings.solverType)")
        }

        guard let flowScaling = StockFlowSimulation.FlowScaling(settings.flowScaling) else {
            throw InternalSystemError(self, message: "Unknown flow scaling: \(settings.flowScaling)")
        }
        
        // TODO: Add flow scaling parameter
        let simulation = StockFlowSimulation(plan, solver: solverType, flowScaling: flowScaling)

        // TODO: This will be removed once we move to SimulationTimeSettings everywhere else
        let timeSettings = SimulationTimeSettings(
            startTime: settings.initialTime,
            timeStep: settings.timeDelta,
            finalTime: settings.endTime
        )
        
        var refParams: [VariableReference:Variant] = [:]
        for (objectID, value) in parameters.values {
            guard let ref = plan.variableReference(objectID) else {
                throw InternalSystemError(self, message: "Parameters not sanitised (offending object ID:\(objectID))")
            }
            refParams[ref] = value
        }
        
        var builder = SimulationResultBuilder(plan: plan,
                                              timeSettings: timeSettings,
                                              parameters: refParams)

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

        builder.append(state: currentState)

        let steps = settings.steps
        var step = 0
                        
        while step < steps {
            let newState = try self.step(simulation: simulation, state: currentState)
            builder.append(state: newState)
            currentState = newState
            step += 1
        }

        let result = builder.build()
        
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
