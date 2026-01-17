//
//  Scenario.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 04/01/2026.
//

import PoieticCore

/// Settings of the simulation – time and solver.
///
/// - SeeAlso: ``ScenarioParameters``.
///
public struct SimulationSettings: Component {
    /// Time of the initialisation state of the simulation.
    public var initialTime: Double
    
    /// Advancement of time for each simulation step.
    public var timeDelta: Double

    /// Number of steps to run.
    ///
    public var steps: UInt
    
    /// Final simulation time.
    ///
    /// Simulation is run while the simulation is less than ``endTime``.
    public var endTime: Double { initialTime + timeDelta * Double(steps) }
    
    /// Solver type name.
    ///
    public var solverType: String
    
    /// Create new simulation settings.
    ///
    /// - Parameters:
    ///     - initialTime: Time of the initialisation state of the simulation.
    ///     - timeDelta: Advancement of time for each simulation step.
    ///     - steps: Number of steps to run.
    ///     - solverType: Name of a solver to be used.
    ///
    public init(initialTime: Double = 0.0,
                timeDelta: Double = 1.0,
                steps: UInt = 10,
                solverType: String = "euler")
    {
        self.initialTime = initialTime
        self.timeDelta = timeDelta
        self.steps = steps
        self.solverType = solverType
    }

    public init(initialTime: Double = 0.0,
                timeDelta: Double = 1.0,
                endTime: Double,
                solverType: String = "euler")
    {
        self.initialTime = initialTime
        self.timeDelta = timeDelta
        if endTime <= initialTime {
            self.steps = 0
        }
        else if let floor = UInt(exactly: ((endTime - initialTime) / timeDelta).rounded(.down)) {
            self.steps = floor
        }
        else {
            self.steps = 0
        }
        self.solverType = solverType
    }

    /// Create new simulation settings from an object.
    ///
    /// The object is expected to be of a ``Trait/Simulation`` type, although any object with
    /// expected attributes can be used.
    ///
    public init(fromObject object: ObjectSnapshot) {
        let initialTime = object["initial_time", default: 0.0]
        let timeDelta = object["time_delta", default: 0.0]
        let solverType = object["solver_type", default: "euler"]

        if let endTime: Double = object["end_time"] {
            self.init(initialTime: initialTime,
                      timeDelta: timeDelta,
                      endTime: endTime,
                      solverType: solverType)
        }
        else if let steps: Int = object["steps"], steps >= 0 {
            self.init(initialTime: initialTime,
                      timeDelta: timeDelta,
                      steps: UInt(steps),
                      solverType: solverType)
        }
        else {
            self.init(initialTime: initialTime,
                      timeDelta: timeDelta,
                      steps: 0,
                      solverType: solverType)
        }
        

    }
}

extension SimulationSettings: InspectableComponent {
    public static let attributeKeys: [String] = [
        "initial_time", "time_delta", "end_time", "steps", "solver_type",
    ]
    public func attribute(forKey key: String) -> Variant? {
        switch key {
        case "initial_time": Variant(self.initialTime)
        case "time_delta": Variant(self.timeDelta)
        case "ent_time": Variant(self.endTime)
        case "steps": Variant(Int(exactly: self.steps) ?? 0)
        case "solver_type": Variant(self.solverType)
        default: nil
        }
    }
}
/// Initial values of simulation variables.
///
/// - SeeAlso: ``SimulationSettings``.
///
public struct ScenarioParameters: Component {
    public let initialValues: [ObjectID:Variant]
    public init(initialValues: [ObjectID:Variant] = [:]) {
        self.initialValues = initialValues
    }
}
