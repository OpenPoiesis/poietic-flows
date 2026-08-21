//
//  SimulationPlanningSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 01/11/2025.
//
import PoieticCore

extension PlanningError {
    func internalSystemErrorContext() -> InternalSystemError.Context {
        let context: InternalSystemError.Context
        switch self {
        case .corruptedComponent(let id, let name):
            context = .component(id, name)
        case .corruptedVariableTable:
            context = .none
        case .invalidObject(let id, _):
            context = .object(id)
        case .missingComponent(let id, let name):
            context = .component(id, name)
        case .unprocessedObjects:
            context = .singleton("SimulationOrder")
        case .userIssue:
            context = .none
        }
        return context
    }
}

/// System that creates the final simulation plan.
///
/// - **Dependency:**
///     - Must run after `ExpressionParserSystem` to parse expressions and get variable names.
///     - Must run after ``ComputationOrderSystem`` to get the simulation order, which is one of the
///       key simulation information.
///     - Must run after ``NameResolutionSystem``.
///     - Must run after ``StockFlowTopologySystem``to collect stocks
///       and flows.
/// - **Input:**
///     - ``SimulationOrder``: singleton, required.
///     - ``SimulationName``: required for simulation objects, otherwise no plan is created.
///     - ``SimulationRole``: required for simulation objects, otherwise no plan is created.
///     - `ParsedExpressionComponent`: semantically required by formula objects.
///     - ``ResolvedParameters``: semantically required – registers an object issue if missing.
///     - ``FlowRate``: required for flow nodes.
///     - ``Stock``: required for stock nodes.
/// - **Output:**
///     - ``SimulationPlan`` singleton is set if there were no issues. If there are issues the
///       existing singleton is removed.
/// - **Forgiveness:** The system is forgiving in a way that it does not fail on semantic errors.
///
/// - Note: If the simulation plan was not produced by the system, it means that the model contained
///         issues that make the model non-interpretable. Issues were set on entities which contain
///         offending data or for an offending structure.
///
public struct SimulationPlanningSystem: System {
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ExpressionParserSystem.self), // Gets us UnboundExpression for each node
        .after(ComputationOrderSystem.self), // Gets us SimulationOrderComponent
        .after(NameResolutionSystem.self), // We need name lookup and object names.
        .after(StockFlowTopologySystem.self),
    ]
    
    public init(_ world: World) { }
    
    public func update(_ world: World) throws (InternalSystemError) {
        guard let order: SimulationOrder = world.singleton()
        else { return }

        world.removeSingleton(SimulationPlan.self)
        
        let planner = SimulationPlanner()

        do {
            let plan = try planner.createPlan(order: order, in: world)
            world.setSingleton(plan)
        }
        catch .userIssue {
            // No plan due to semantic (user) errors, otherwise we are fine.
        }
        catch {
            let context = error.internalSystemErrorContext()
            throw InternalSystemError(self,
                                      message: "Unable to create simulation plan",
                                      context: context)
        }
    }
}

/// System that extracts simulation settings from a plane.
///
/// - **Dependency:** None.
/// - **Input:**
///     - Object with a trait `Simulation`.
/// - **Output:** ``SimulationSettings`` singleton if the corresponding object exists
///   in the plane.
/// - **Forgiveness:** Nothing to be forgiven.
///
/// This system should be run after world plane change to get simulation settings defaults.
/// If the plane does not contain an object with `Simulation` trait, the settings singleton
/// is removed.
///
public struct SimulationSettingsSystem: System {
    public init(_ world: World) {
        // Nothing
    }
    public func update(_ world: World) throws (InternalSystemError) {
        guard let plane = world.plane,
              let object = plane.first(trait: Trait.Simulation)
        else {
            world.removeSingleton(SimulationSettings.self)
            return
        }

        let settings = SimulationSettings(fromObject: object)
        world.setSingleton(settings)
    }
}
