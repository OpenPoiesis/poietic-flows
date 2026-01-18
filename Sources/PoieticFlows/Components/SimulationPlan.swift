//
//  SimulationPlan.swift
//
//
//  Created by Stefan Urbanek on 05/06/2022.
//

import PoieticCore

/// Structure according to which a simulation is performed.
///
/// The design describes the model from user's perspective. The content and data structures needed
/// for the modelling process – for the editing – are different than the data used by the machine to
/// perform the simulation. Simulation plan is contains validated and derived information from the
/// design.
///
/// The simulation plan is created by the ``SimulationPlanningSystems`` and typically used by the
/// ``StockFlowSimulationSystem``. It can be also used to explain the simulation process (loosely
/// analogous to a SQL explain plan).
///
/// The primary content of the simulation plan is:
///
/// - List of simulation objects ``SimulationObject`` in order of their computational dependency: ``simulationObjects``.
/// - Structure of the simulation state, list of state variables ``StateVariable``: ``stateVariables``.
/// - List of stocks with inflows and outflows resolved (``BoundStock``).
/// - List of flows with resolved stocks that the flow drains and fills (``BoundFlow``).
///
/// - SeeAlso: ``StockFlowSimulationSystem``, ``SimulationPlanningSystems``.
///
public struct SimulationPlan {
    internal init(simulationObjects: [SimulationObject] = [],
                  stateVariables: [StateVariable] = [],
                  builtins: BoundBuiltins = BoundBuiltins(),
                  stocks: [BoundStock] = [],
                  flows: [BoundFlow] = [],
//                  charts: [Chart] = [],
                  valueBindings: [CompiledControlBinding] = [],
                  simulationParameters: SimulationSettings? = nil) {
        self.simulationObjects = simulationObjects
        self.stateVariables = stateVariables
        self.builtins = builtins
        self.stocks = stocks
        self.flows = flows
//        self.charts = charts
        self.valueBindings = valueBindings
        self.simulationSettings = simulationParameters
    }
    
    /// List of objects that are considered in the computation computed, ordered by computational
    /// dependency.
    ///
    /// The computational dependency means, that the objects are ordered so that objects that do
    /// not require other objects to be computed, such as constants are at the beginning. The
    /// objects that depend on others by using them as a parameter follow the variables they depend
    /// on.
    ///
    /// Computing objects in this order assures that we have all the parameters computed when
    /// they are needed.
    ///
    /// The order is computed by the ``ComputationOrderSystem`` and then filled with details in the
    /// ``SimulationPlanningSystem``.
    ///
    /// - SeeAlso: ``variableIndex(_:)``
    ///
    public let simulationObjects: [SimulationObject]
    
    /// List of simulation state variables.
    ///
    /// The list of state variables contain values of simulation objects (usually nodes) their
    /// internal states (for example previous values for delay) and built-ins.
    ///
    /// Simulation object's state might be contained in multiple state variables. For example, delay
    /// uses two state variables: list of double values for the queue and an initial value.
    ///
    /// The internal state is typically not to be presented to the user.
    ///
    /// - SeeAlso: ``SimulationPlanningSystem``.
    ///
    public let stateVariables: [StateVariable]
    
    /// List of compiled builtin variables.
    ///
    /// The compiled builtin variable references a state variable that holds
    /// the value for the builtin variable and a kind of the builtin variable.
    ///
    public let builtins: BoundBuiltins
    
    
    /// Stocks with resolved inflows and outflows, ordered by the computation dependency.
    ///
    /// - SeeAlso: ``BoundStock``, ``StockFlowSimulationSystem``.
    ///
    public let stocks: [BoundStock]
    
    /// Flows with resolved stocks the flow drains and fills.
    ///
    /// - SeeAlso: ``BoundFlow``, ``StockFlowSimulationSystem``.
    ///
    public let flows: [BoundFlow]
    
    /// Compiled bindings of controls to their value objects.
    ///
    public let valueBindings: [CompiledControlBinding]
    
    /// Time range, time delta and other settings to control the simulation.
    ///
    /// See ``SimulationSettings`` for more information.
    ///
    public let simulationSettings: SimulationSettings?
    
    /// Get index into a list of computed variables for an object with given ID.
    ///
    /// This function is just for inspection and debugging purposes, it is not
    /// used during computation.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso:  ``stateVariables``, ``simulationObject(_:)``
    ///
    public func variableIndex(_ id: ObjectID) -> SimulationState.Index? {
        // Since this is just for debug purposes, O(n) should be fine, no need
        // for added complexity of the code.
        guard let first = simulationObjects.first(where: {$0.objectID == id}) else {
            return nil
        }
        return first.variableIndex
    }
    
    /// Get a simulation variable for an object with given ID, if exists.
    ///
    /// This function is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso: ``simulationObjects``, ``variableIndex(_:)``
    ///
    public func simulationObject(_ id: ObjectID) -> SimulationObject? {
        return simulationObjects.first { $0.objectID == id }
        
    }
    
    /// Get a compiled variable by its name.
    ///
    /// This function is mostly for user-facing tools that would like to
    /// interfere with the simulation state. Example use-cases are:
    ///
    /// - querying the state by variable name
    /// - modifying state variables by user provided variable values
    ///
    /// Since the function is slow, it is highly not recommended to be used
    /// during iterative computation.
    ///
    /// This property is not used during computation, it is provided for
    /// consumers of the simulation state or simulation result.
    ///
    /// - Complexity: O(n)
    ///
    public func variable(named name: String) -> SimulationObject? {
        guard let object = simulationObjects.first(where: { $0.name == name}) else {
            return nil
        }
        
        return object
    }
}

