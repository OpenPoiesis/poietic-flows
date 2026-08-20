//
//  CompilationSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 01/11/2025.
//
import PoieticCore

// TODO: Do state variables need name? Can it be optional?


/// System that creates the final simulation plan.
///
/// - **Dependency:**
///     - Must run after `ExpressionParserSystem` to parse expressions and get variable names.
///     - Must run after ``ComputationOrderSystem`` to get the simulation order, which is one of the
///       key simulation information.
///     - Must run after ``NameResolutionSystem``.
///     - Must run after ``FlowCollectorSystem`` and ``StockDependencySystem`` to collect stocks
///       and flows.
/// - **Input:**
///     - ``SimulationOrderComponent``: singleton, required.
///     - ``SimulationObjectNameComponent``: required for simulation objects, otherwise no plan is created.
///     - ``SimulationRoleComponent``: required for simulation objects, otherwise no plan is created.
///     - `ParsedExpressionComponent`: semantically required by formula objects.
///     - ``ResolvedParametersComponent``: semantically required – registers an object issue if missing.
///     - ``FlowRateComponent``: required for flow nodes.
///     - ``StockComponent``: required for stock nodes.
/// - **Output:** ``SimulationPlan`` singleton if there were no issues, otherwise sets object issues.
/// - **Forgiveness:** The system is forgiving in a way that it does not fail on semantic errors.
///
/// - Note: If the simulation plan was not produced by the system, it means that the model contained
///         issues that make the model non-interpretable. Issues were set on entities which contain
///         offending data or for an offending structure.
///
public struct SimulationPlanningSystem: System {
    // TODO: [IMPORTANT] Break this down. Requires verification mechanism that all has been considered (no intermediate forgiveness)
    /// Error thrown during the planning process
    internal enum CompilationError: Error, Equatable {
        /// Issue with object has been detected, appended to the list of issues. The caller might
        /// continue with the operation to gather more issues. Criticality of this error is
        /// problem specific.
        case objectIssue
        case corruptedState(String)
        /// Missing required component. Probably the dependency was not satisfied.
        case missingComponent(String)
    }
    
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ExpressionParserSystem.self), // Gets us UnboundExpression for each node
        .after(ComputationOrderSystem.self), // Gets us SimulationOrderComponent
        .after(NameResolutionSystem.self), // We need name lookup and object names.
        .after(StockFlowTopologySystem.self),
    ]
    
    public init(_ world: World) {
        // Nothing any more
    }
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
