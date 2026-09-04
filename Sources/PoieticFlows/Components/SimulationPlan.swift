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
/// perform the simulation. Simulation plan contains validated and derived information from the
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
/// - **Produced by:** ``SimulationPlanningSystem``
/// - **Used by:** ``StockFlowSimulationSystem`` and your application
///
/// ## Plan Integrity
///
/// Simulation plan integrity is enforced on multiple levels. Higher levels assume lower
/// ones held.
///
/// - **Level 1: Structural**. Structural integrity and conformance to metamodel assured by
///   `Design` on acceptance.
/// - **Level 2: Semantic**. Each system that produces artefacts consumed by the
///   ``SimulationPlanningSystem`` records user-facing errors.
/// - **Level 3: Planning**. The planning system refuses to produce a plan if there are semantic
///   errors (user's responsibility) and throws on internal inconsistencies
///   (developer's responsibility).
///
/// - SeeAlso: ``StockFlowSimulationSystem``, ``SimulationPlanningSystems``.
///
public final class SimulationPlan: Component {
    // Keep the SimulationPlan by reference.
    // TODO: Add simulation settings
    // TODO: Add time settings
    
    internal init(simulationObjects: [SimulationObject] = [],
                  stateVariables: [StateVariable] = [],
                  stocks: [BoundStock] = [],
                  flows: [BoundFlow] = [],
                  numericVariableCount: Int,
                  variantVariableCount: Int)
    {
        self.simulationObjects = simulationObjects
        self.stateVariables = stateVariables
        self.stocks = stocks
        self.flows = flows
        self.numericVariableCount = numericVariableCount
        self.variantVariableCount = variantVariableCount
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
    /// The list of state variables defines the state vector layout and content.
    ///
    /// Simulation object's state might be contained in multiple state variables. For example, delay
    /// uses two state variables: list of double values for the queue and an initial value.
    ///
    /// The internal state is typically not to be presented to the user.
    ///
    /// - SeeAlso: ``StateVariable``, ``SimulationPlanningSystem``.
    ///
    public let stateVariables: [StateVariable]
    
    
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
    
    // State allocation information
    // TODO: Can't we compute that from stateVariables?
    /// Number of numeric variables needed to be allocated.
    public let numericVariableCount: Int

    /// Number of variant variables needed to be allocated.
    public let variantVariableCount: Int
    
    /// Get index into a list of computed variables for an object with given ID.
    ///
    /// This function is just for inspection and debugging purposes, it is not
    /// used during computation.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso:  ``stateVariables``, ``simulationObject(_:)``
    ///
    public func variableReference(_ id: ObjectID) -> SimulationState.Reference? {
        // Since this is just for debug purposes, O(n) should be fine, no need
        // for added complexity of the code.
        guard let first = simulationObjects.first(where: {$0.objectID == id}) else {
            return nil
        }
        return first.variableReference
    }
    
    /// List of all normalised object names.
    public var objectNameKeys: [String] { simulationObjects.map {$0.nameKey} }
    
    /// Get a simulation object with given ID, if exists.
    ///
    /// - Note: This function is not used during computation, it is provided for
    ///   consumers of the simulation state or simulation result.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso: ``simulationObjects``, ``variableIndex(_:)``
    ///
    public func simulationObject(_ id: ObjectID) -> SimulationObject? {
        return simulationObjects.first { $0.objectID == id }
    }
    
    // TODO: Consider objectID -> simulation object index map
    /// Check whether the plan contains a simulation object with given ID.
    public func containsObject(_ id: ObjectID) -> Bool {
        return simulationObjects.contains { $0.objectID == id }
    }
    
    /// Get a simulation object with given normalised name, if exists.
    ///
    /// - Note: This function is not used during computation, it is provided for
    ///   consumers of the simulation state or simulation result.
    ///
    /// - Complexity: O(n)
    /// - SeeAlso: ``simulationObjects``, ``variableIndex(_:)``
    ///
    public func simulationObject(withKey nameKey: String) -> SimulationObject? {
        return simulationObjects.first { $0.nameKey == nameKey }
    }
    
    /// Get a state variable by its normalised name.
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
    /// - Note: This property is not used during computation, it is provided for
    ///   consumers of the simulation state or simulation result.
    ///
    /// - Complexity: O(n)
    ///
    public func variable(withKey nameKey: String) -> StateVariable? {
        return stateVariables.first(where: { $0.name == nameKey})
    }
    
    /// State variable with the given state reference.
    public func variable(for reference: SimulationState.Reference) -> StateVariable? {
        stateVariables.first { $0.reference == reference }
    }

    /// Primary state variable of an object.
    ///
    /// For flow this is the applied flow.
    public func variable(forObject objectID: ObjectID) -> StateVariable? {
        stateVariables.first { $0.content == .object(objectID) }
    }

    /// State variable of a builtin.
    public func variable(forBuiltin builtin: BuiltinVariable) -> StateVariable? {
        stateVariables.first { $0.content == .builtin(builtin) }
    }

    /// List of all normalised state variable names, including internal ones.
    public var variableNameKeys: [String] { stateVariables.map {$0.name} }
    
    /// Return a set of default variables - simulation time and all object variables.
    public var defaultVariables: [StateVariable] {
        var result: [StateVariable] = []
        
        if let time = variable(forBuiltin: .time) {
            result.append(time)
        }

        for object in self.simulationObjects {
            guard let variable = self.variable(forObject: object.objectID)
            else { continue }
            result.append(variable)
        }
        return result
    }
    
    /// Return list of variables with given name, if found.
    ///
    /// - Parameters:
    ///     - names: List of variable names. Each name will be normalised first before matching with
    ///       actual variable.
    ///     - includeTime: Include built-in time variable, even if it is not included in the
    ///       list of names.
    ///
    /// If variable with given name was not found, `nil` is included in the output, so that the
    /// caller can later either report it as unknown or ignore it.
    ///
    /// - Note: The `includeTime` is disregarded, if time variable is specified in the list.
    ///
    public func variables(named names: [String], includeTime: Bool = true) -> (known: [StateVariable], unknown: [String]) {
        let keys = names.map { NormalizedName.normalize($0) }
        let timeKey = BuiltinVariable.time.normalizedKey
        
        var result: [StateVariable] = []
        var unknown: [String] = []
        
        if includeTime && !keys.contains(timeKey),
           let time = variable(forBuiltin: .time)
        {
            result.append(time)
        }
        
        for (key, name) in zip(keys, names) {
            if let variable = self.variable(withKey: key) {
                result.append(variable)
            }
            else {
                unknown.append(name)
            }
        }
        return (known: result, unknown: unknown)
    }

}

