//
//  StockFlowSimulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

// TODO: [IMPORTANT] Set object issues when computation fails (for example value conversion, or division by zero). Do not throw.
// TODO: Halt on negative inflow or outflow (optional)

import PoieticCore

public enum SimulationError: Error, CustomStringConvertible {
    case unknownObject(ObjectID)
    case evaluation(ObjectID, EvaluationError)
    case stateValue(ObjectID, SimulationState.Reference, ValueError)
    case atomExpected(ObjectID)

    public var description: String {
        switch self {
        case let .evaluation(id , error): "Evaluation of \(id) failed: \(error)"
        case let .unknownObject(id): "Unknown object \(id)"
        case let .stateValue(id, ref, error): "State value error for \(id), ref: \(ref): \(error)"
        case .atomExpected: "Value is expected to be an atom"
        }
    }
}

/// Stock-Flow simulation specific computation and logic.
///
public class StockFlowSimulation {
    /// Simulation plan according which the computation is performed.
    ///
    public let plan: SimulationPlan
    
    public enum FlowScaling: String, RawRepresentable, CaseIterable {
        case inflowFirst
        case outflowFirst
        // case balanced
    }
    
    public enum SolverType: String, RawRepresentable, CaseIterable {
        case euler
        case rk4
    }
    
    /// Type of a solver to be used for the simulation.
    public var solver: SolverType
    public var flowScaling: FlowScaling
    
    /// Create a new Stock Flow simulation for a specific model.
    ///
    public init(_ plan: SimulationPlan, solver: SolverType = .euler, flowScaling: FlowScaling = .outflowFirst) {
        self.plan = plan
        self.solver = solver
        self.flowScaling = flowScaling
    }
   
    // MARK: - Initialization

    // MARK: - Computation
    
    /// Update the simulation state.
    ///
    /// This is the main method that performs the concrete computation using a concrete solver.
    ///
    public func step(_ state: SimulationState) throws (SimulationError) -> SimulationState {
        let result: SimulationState
        
        switch solver {
        case .euler: result = try integrateWithEuler(state)
        case .rk4: result = try integrateWithRK4(state)
        }
        
        return result
    }
    
    internal func write(_ value: Variant,
                      to reference: SimulationState.Reference,
                      of objectID: ObjectID,
                      in state: inout SimulationState)
    throws (SimulationError)
    {
        do {
            try state.setValue(value, for: reference)
        }
        catch {
            throw .stateValue(objectID, reference, error)
        }
        
    }
}
