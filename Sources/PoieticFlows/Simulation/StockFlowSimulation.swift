//
//  StockFlowSimulation.swift
//  PoieticFlows
//
//  Created by Stefan Urbanek on 28/10/2024.
//

// TODO: [IMPORTANT] Set object issues when computation fails (for example value conversion, or division by zero). Do not throw.
// TODO: Halt on negative inflow or outflow (optional)

import PoieticCore

// for evaluation
extension SimulationState: VariableValueLookup {
    public typealias Variable = BoundVariable
    public func value(for variable: Variable) -> Variant {
        return self[variable.index]
    }
}

public enum SimulationError: Error, CustomStringConvertible {
    case evaluationError(ObjectID, EvaluationError)
    case unknownObject(ObjectID)
    
    public var description: String {
        switch self {
        case let .evaluationError(id , error): "Evaluation of \(id) failed: \(error)"
        case let .unknownObject(id): "Unknown object \(id)"
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
        self.constantIndices = Set()
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

    /// Creates a copy of a state and advances the time.
    ///
    /// The returned state has time-dependent built-in variables updated.
    ///
    /// This is a designated method to get a new state before performing computation of the next
    /// step.
    ///
    public func advance(_ state: SimulationState, time: Double? = nil, timeDelta: Double? = nil) -> SimulationState {
        var newState = state.advanced(time: time, timeDelta: timeDelta)
        setBuiltins(in: &newState)
        return newState
    }
    
    func evaluateFlows(_ state: SimulationState) -> NumericVector {
        var result = NumericVector(zeroCount: plan.flows.count)
        for (i, flow) in plan.flows.enumerated() {
            result[i] = state[flow.estimatedValueIndex]
        }
        return result
    }
    
    public func updateAuxiliariesAndFlows(in state: inout SimulationState) throws (SimulationError) {
        for object in plan.simulationObjects {
            guard object.role == .auxiliary || object.role == .flow else { continue }
            try evaluate(object: object, in: &state)
        }
    }
    
}
