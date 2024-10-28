//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 05/09/2023.
//


import PoieticCore

// TODO: [REVIEW] Consolidate SimulationState and SimulationContext

/// Protocol for systems that support the simulation.
///
/// The simulation system operates in two phases: compilation and simulation.
/// The compilation phase transforms the design into an internal representation
/// that can be interpreted. The simulation phase is an iterative phase
/// of simulation steps.
///
/// The typical flow is:
///
/// 1. Prepare for compilation with ``SimulationContext``
/// 2. Perform tasks after compilation
///
/// - Note: This is experimental protocol for exploring ways of simulator extensibility,
///   so the simulator can be later generalised and moved into the PoieticCore
///   package.
///
public protocol SimulationSystem {
    /// Update the design with custom objects, before compilation
    ///
    /// This method is called when:
    ///
    /// - Model has been edited
    /// - Simulation was reset, when running interactive simulation
    ///
//    func prepareForCompilation(_ context: CompilationContext)
    /// Compiled model has been created, use it
//    func didCompile(_ context: CompilationContext, model: CompiledModel)

    /// Called before the first step of the simulation is run.
    func didInitialize(_ context: SimulationContext)

    // TODO: Rename to update() and remove didStop(), use some flag in context, for example "isRunning"
    /// Simulation step has been finished
    func didStep(_ context: SimulationContext)
    /// The simulation has been finished
    func didRun(_ context: SimulationContext)
}

extension SimulationSystem {
//    public func prepareForCompilation(_ context: CompilationContext) {
//        // Do nothing
//    }

//    public func didCompile(_ context: CompilationContext, model: CompiledModel) {
//        // Do nothing
//    }

    public func didInitialize(_ context: SimulationContext) {
        // Do nothing
    }

    public func didStep(_ context: SimulationContext) {
        // Do nothing
    }

    public func didRun(_ context: SimulationContext) {
        // Do nothing
    }
}

// MARK: - Systems
#if false
public struct ControlBindingSystem: SimulationSystem {
    public func didInitialize(_ context: SimulationContext) {
        updateValues(context)
    }
    
    public func didStep(_ context: SimulationContext) {
        updateValues(context)
    }

    public func updateValues(_ context: SimulationContext) {
        for binding in context.model.valueBindings {
            let value = context.state.computedValues[binding.variableIndex]
            let control = context.frame.mutableObject(binding.control)
            control["value"] = Variant(value)
        }
    }
}

#endif
