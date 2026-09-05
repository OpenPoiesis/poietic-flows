//
//  Scenario.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 04/01/2026.
//

import PoieticCore

// TODO: StockFlowSimulationSettings + SimulationTimeSettings (now in core) will replace SimulationSettings
public struct StockFlowSimulationSettings: Component {
    public var solver: StockFlowSimulation.SolverType
    public var flowScaling: StockFlowSimulation.FlowScaling
    
    /// Create new simulation settings from an object.
    ///
    /// Expected keys:
    /// - `solver_type`, default value `euler`
    /// - `flow_scaling`, default value `inflow_first`
    ///
    /// - SeeAlso: ``StockFlowSimulation/SolverType``, ``StockFlowSimulation/FlowScaling``
    ///
    public init(fromObject object: ObjectSnapshot) {
        let solverType: String = object["solver_type"] ?? "euler"
        let flowScaling: String = object["flow_scaling"] ?? "outflow_first"

        self.solver = .init(solverType) ?? .euler
        self.flowScaling = .init(flowScaling) ?? .inflowFirst
    }
}

/// Settings of the simulation – time and solver.
///
/// - SeeAlso: ``ScenarioParameters``.
///
public struct SimulationSettings: Component {
    // TODO: Rename to SimulationTime and move to Core
    // TODO: Split solver and add
    // TODO: Rename "end time" to "stop time" or "final time" (preferred)
    /// Time of the initialisation state of the simulation.
    public var initialTime: Double
    
    /// Advancement of time for each simulation step.
    public var timeDelta: Double

    /// Final simulation time.
    ///
    /// Simulation is run while the simulation is less than ``endTime``.
    public var endTime: Double

    /// Number of steps to run.
    ///
    public var steps: Int {
        if timeDelta > 0 {
            let value = ((endTime - initialTime) / timeDelta )
            return Int((value + 1e-9).rounded(.down))
        }
        else {
            return 0
        }
        
    }
        
    // TODO: Move somewhere else, separate component. Keep this computation-free (unless generic enough)
    /// Solver type name.
    ///
    public var solverType: String
    public var flowScaling: String


    /// Create new simulation settings.
    ///
    /// - Parameters:
    ///     - initialTime: Time of the initialisation state of the simulation.
    ///     - timeDelta: Advancement of time for each simulation step.
    ///     - endTime: Final simulation time.
    ///     - solverType: Name of a solver to be used.
    ///
    public init(initialTime: Double = 0.0,
                timeDelta: Double = 1.0,
                endTime: Double = 10.0,
                solverType: String = "euler",
                flowScaling: String = "outflow_first")
    {
        self.initialTime = initialTime
        self.timeDelta = timeDelta
        self.endTime = max(self.initialTime, endTime)
        self.solverType = solverType
        self.flowScaling = flowScaling
    }

    @available(*, deprecated, message: "Use end time")
    public init(initialTime: Double = 0.0,
                timeDelta: Double = 1.0,
                steps: Int,
                solverType: String = "euler",
                flowScaling: String = "outflow_first")
    {
        self.initialTime = initialTime
        self.timeDelta = timeDelta
        self.endTime = initialTime + Double(steps) * timeDelta
        self.solverType = solverType
        self.flowScaling = flowScaling
    }

    /// Create new simulation settings from an object.
    ///
    /// The object is expected to have the `Simulation` trait, although any object with
    /// expected attributes can be used.
    ///
    /// If the object has both `end_time` and `steps`, then `end_time` takes priority.
    ///
    public init(fromObject object: ObjectSnapshot) {
        let initialTime = object["initial_time", default: 0.0]
        let timeDelta = object["time_delta", default: 1.0]
        let solverType = object["solver_type", default: "euler"]
        let flowScaling = object["flow_scaling", default: "outflow_first"]

        if let endTime: Double = object["end_time"] {
            self.init(initialTime: initialTime,
                      timeDelta: timeDelta,
                      endTime: endTime,
                      solverType: solverType,
                      flowScaling: flowScaling)
        }
        else if let steps: Int = object["steps"], steps >= 0 {
            self.init(initialTime: initialTime,
                      timeDelta: timeDelta,
                      steps: steps,
                      solverType: solverType,
                      flowScaling: flowScaling)
        }
        else {
            self.init(initialTime: initialTime,
                      timeDelta: timeDelta,
                      steps: 0,
                      solverType: solverType,
                      flowScaling: flowScaling)
        }
        

    }
}

/// Initial values of simulation variables.
///
/// - SeeAlso: ``SimulationSettings``.
///
public struct ScenarioParameters: Component {
    public let values: [ObjectID:Variant]
    public init(values: [ObjectID:Variant] = [:]) {
        self.values = values
    }
}
