//
//  Solver.swift
//  
//
//  Created by Stefan Urbanek on 27/07/2022.
//
import PoieticCore

/*
 
 INIT:
    FOR EACH stock
        compute value # requires aux
 
 ITERATE:
 
    STORE initial state # make it current/last state
 
    FOR EACH STAGE:
        FOR EACH aux
            compute value
        FOR EACH flow
            compute flow rate
    ESTIMATE flows
 
 */

/// An abstract class for equations solvers.
///
/// Purpose of a solver is to initialise values of the nodes and then
/// to compute and integrate each step of the simulation.
///
/// Solver is using a ``CompiledModel``, which is guaranteed to be correct
/// for computation.
///
/// The main method of the solver is ``compute(_:at:timeDelta:)``, which is
/// provided by concrete subclasses of the solver.
///
/// To use the solver, it needs to be initialised first, then the
/// ``compute(_:at:timeDelta:)`` is called for each step of the simulation.
///
/// ```swift
/// // Assume we have a compiled model.
/// let compiled: CompiledModel
///
/// let solver = EulerSolver(compiled)
///
/// var time: Double = 0.0
/// let timeDelta: Double = 1.0
///
/// var state: StateVector = solver.initializeState(time: time,
///                                                 timeDelta: timeDelta)
///
/// for step in (1...100) {
///     time += timeDelta
///     state = try solver.compute(state,
///                                at: time,
///                                timeDelta: timeDelta)
///     print(state)
/// }
/// ```
///
/// To get a solver by name:
///
/// ```swift
/// // Assume this is given, provided by the user or in a configuration.
/// let solverTypeName: String
/// guard let solverType = Solver.registeredSolvers[solverTypeName] else {
///     fatalError("Unknown solver: \(solverTypeName)")
/// }
///
/// let solver = solverType.init()
///
/// // ... now we can use the solver
/// ```
///
public class Solver {
    /// Compiled model that the solver is solving for.
    ///
    /// The compiled model is created using the ``Compiler``.
    ///
    ///
    /// - SeeAlso: ``Compiler``
    ///
    public let compiledModel: CompiledModel
    
    /// Values of constants (auxiliaries) to be replaced.
    ///
    /// This mapping is typically used to replace values of constants by
    /// controls.
    ///
    public var constants: [ObjectID:Variant]

    nonisolated(unsafe) public static let Variables: [Variable] = [
        Variable.TimeVariable,
        Variable.TimeDeltaVariable,
    ]

    /// Return list of registered solver names.
    ///
    /// The list is alphabetically sorted, as the typical usage of this method is
    /// to display the list to the user.
    ///
    nonisolated(unsafe)
    public static var registeredSolverNames: [String] {
        return registeredSolvers.keys.sorted()
    }
    
    /// A dictionary of registered solver types.
    ///
    /// The key is the solver name and the value is the solver class (type).
    ///
    nonisolated(unsafe) 
    public static private(set) var registeredSolvers: [String:Solver.Type] = [
        "euler": EulerSolver.self,
        "rk4": RungeKutta4Solver.self,
    ]
    
    /// Register a solver within the solver registry.
    ///
    /// Registered solvers can be retrieved through the ``registeredSolvers``
    /// dictionary.
    ///
    /// - Note: Solvers do not have to be registered if there is other method
    /// provided for the user to get a desired solver.
    ///
    @MainActor
    public static func registerSolver(name: String, solver: Solver.Type) {
        registeredSolvers[name] = solver
    }
    
    /// Create a solver.
    ///
    /// The provided ``CompiledModel`` is typically created by the ``Compiler``.
    /// It is guaranteed to be consistent and useable by the solver without
    /// any issues. Design that contains errors that would prevent correct
    /// computation are prevented from being compiled.
    ///
    /// - Note: Do not use this method on this abstract class. Use a concrete
    ///   solver subclass, such as ``EulerSolver`` or ``RungeKutta4Solver``
    ///
    public required init(_ compiledModel: CompiledModel) {
        // TODO: How to make this private? (see note below)
        // If this method is made private, we can't create instances of solver
        // if we get the solver type through registeredSolvers.
        //
        
        self.compiledModel = compiledModel
        // TODO: Pass overrides in init()
        self.constants = [:]
    }

    /// Initialise the computation state.
    ///
    /// - Parameters:
    ///     - `time`: Initial time. This parameter is usually not used, but
    ///     some computations in the model might use it. Default value is 0.0
    ///     - `override`: Dictionary of values to override during initialisation.
    ///     The values of nodes that are present in the dictionary will not be
    ///     evaluated, but the value from the dictionary will be used.
    ///
    /// This function computes the initial state of the computation by
    /// evaluating all the nodes in the order of their dependency by parameter.
    ///
    /// - Returns: `StateVector` with initialised values.
    ///
    /// - Precondition: The compiled model must be valid. If the model
    ///   is not valid and contains elements that can not be computed
    ///   correctly, such as invalid variable references, this function
    ///   will fail.
    ///
    /// - Note: Use only constants in the `override` dictionary. Even-though
    ///   any node value can be provided, in the future only constants will
    ///   be allowed.
    ///
    /// - Note: Values for stocks in the `override` dictionary will be used
    ///   only during initialisation.
    ///
    public func initializeState(override: [ObjectID:Double] = [:],
                                time: Double = 0.0,
                                timeDelta: Double = 1.0) throws -> SimulationState {

        // FIXME: make override [ObjectID:Variant] and validate types(?)
        self.constants = [:]
        var state = SimulationState(model: compiledModel)
        updateBuiltins(&state, time: time, timeDelta: timeDelta)

        for (index, object) in compiledModel.simulationObjects.enumerated() {
            if let value = override[object.id] {
                state[object.variableIndex] = Variant(value)

                // Keep only overrides for auxiliaries
                if object.type == .auxiliary {
                    self.constants[object.id] = Variant(value)
                }
            }
            else {
                let result = try initialize(objectAt: index,
                                            with: &state)
                state[object.variableIndex] = result
            }
        }
        
        return state
    }

    public func updateBuiltins(_ state: inout SimulationState,
                               time: Double = 0.0,
                               timeDelta: Double = 1.0) {
        
        for variable in compiledModel.builtins {
            let value: Variant

            switch variable.builtin {
            case .time:
                value = Variant(time)
            case .timeDelta:
                value = Variant(timeDelta)
            }
            state[variable.variableIndex] = value
        }
    }

    /// Compute auxiliaries and flows for given stage of the computation step.
    ///
    /// Stocks are skipped.
    ///
    /// If solvers use multiple stages, they must call this method if they do
    /// not prepare the state by themselves.
    ///
    /// The ``EulerSolver`` uses only one stage, the ``RungeKutta4Solver`` uses
    /// 4 stages.
    ///
    func update(_ state: inout SimulationState,
                at time: Double,
                timeDelta: Double = 1.0) throws {
       
        for (index, object) in compiledModel.simulationObjects.enumerated() {
            // Skip the stocks
            if object.type == .stock {
                continue
            }
            let value = try evaluate(objectAt: index,
                                     with: &state)
            state[object.variableIndex] = value
        }
    }
    
    /// Initialise an object.
    ///
    /// - Parameters:
    ///     - index: Index of the object to be evaluated.
    ///     - state: simulation state within which the expression is evaluated
    ///
    /// - Returns: an evaluated value of the expression.
    ///
    public func initialize(objectAt index: Int,
                         with state: inout SimulationState) throws -> Variant {
        let object = compiledModel.simulationObjects[index]
        if let value = constants[object.id] {
            return value
        }
        
        switch object.computation {

        case let .formula(expression):
            return try evaluate(expression: expression,
                                with: state)
            
        case let .graphicalFunction(function, index):
            let value = state[index]
            return try function.apply([value])
        case let .delay(delay):
            return try initialize(delay: delay,
                                  with: &state)
        }
    }

    /// Evaluate an object within the context of a simulation state.
    ///
    /// - Parameters:
    ///     - index: Index of the object to be evaluated.
    ///     - state: simulation state within which the expression is evaluated
    ///
    /// - Returns: an evaluated value of the expression.
    ///
    public func evaluate(objectAt index: Int,
                         with state: inout SimulationState) throws -> Variant {
        let object = compiledModel.simulationObjects[index]
        if let value = constants[object.id] {
            return value
        }
        
        switch object.computation {

        case let .formula(expression):
            return try evaluate(expression: expression,
                                with: state)
            
        case let .graphicalFunction(function, index):
            let value = state[index]
            return try function.apply([value])
        case let .delay(delay):
            return try evaluate(delay: delay,
                                with: &state)
        }
    }

    public func evaluate(expression: BoundExpression,
                         with state: SimulationState) throws -> Variant {
        switch expression {
        case let .value(value):
            return value

        case let .binary(op, lhs, rhs):
            return try op.apply([try evaluate(expression: lhs, with: state),
                                 try evaluate(expression: rhs, with: state)])

        case let .unary(op, operand):
            return try op.apply([try evaluate(expression: operand, with: state)])

        case let .function(functionRef, arguments):
            let evaluatedArgs = try arguments.map {
                try evaluate(expression: $0, with: state)
            }
            return try functionRef.apply(evaluatedArgs)

        case let .variable(variable):
            return state[variable.index]
        }
    }

    public func initialize(delay: CompiledDelay,
                           with state: inout SimulationState) throws -> Variant {
        let outputValue: Variant
        if let intialValue = delay.initialValue {
            outputValue = intialValue
        }
        else {
            let inputValue =
            outputValue = state[delay.inputValueIndex]
        }
        // FIXME: [IMPORTANT] THIS NEEDS delay.valueType + Variant refactoring (we reached its limits)
        state[delay.queueIndex] = .array(VariantArray(type: .double))
        print("STATE QUEUE INIT: \(state[delay.queueIndex])")
        
        return outputValue
    }
    
    public func evaluate(delay: CompiledDelay,
                         with state: inout SimulationState) throws -> Variant {
        guard case let .atom(inputValue) = state[delay.inputValueIndex] else {
            // TODO: Runtime error
            fatalError("Expected atom for delay input value, got array (runtime error)")
        }
        guard case var .array(queue) = state[delay.queueIndex] else {
            fatalError("Expected array for delay queue, got atom (compilation is corrupted)")
        }
        print("STATE QUEUE AT \(queue.count): \(queue)")
        let outputValue: VariantAtom
        let nextValue: VariantAtom // Value to be pushed
        
        // TODO: Use `step` as future function parameter instead of this workaround for queue lenght
        if queue.count + 1 < delay.steps {
            guard case let .atom(initialValue) = state[delay.initialValueIndex] else {
                // TODO: Runtime error
                fatalError("Expected atom for delay initial value, got array (runtime error)")
            }

            // We do have at least one value in the array (see initialize(delay:...))
            outputValue = initialValue
            nextValue = initialValue
        }
        else {
            outputValue = queue.remove(at:0)
            nextValue = inputValue
        }
        queue.append(nextValue)
        state[delay.queueIndex] = .array(queue)

        return .atom(outputValue)
    }

    /// - Important: Do not use for anything but testing or debugging.
    ///
    func computeStockDelta(_ id: ObjectID,
                           at time: Double,
                           with state: inout SimulationState) throws -> Double {
        let stock = compiledModel.compiledStock(id)
        return try self.computeStockDelta(stock,
                                          at: time,
                                          with: &state)
    }
    
    // TODO: [RELEASE] Review documentation
    /// Compute a difference of a stock.
    ///
    /// This function computes amount which is expected to be drained from/
    /// filled in a stock.
    ///
    /// - Parameters:
    ///     - stock: Stock for which the difference is being computed
    ///     - time: Simulation time at which we are computing
    ///     - state: Simulation state vector
    ///
    /// The flows in the state vector will be updated based on constraints.
    /// For example, if the model contains non-negative stocks and a flow
    /// trains a stock with multiple outflows, then other outflows must be
    /// adjusted or set to zero.
    ///
    /// - Note: Current implementation considers are flows to be one-directional
    ///         flows. Flow with negative value, which is in fact an outflow,
    ///         will be ignored.
    ///
    /// - Precondition: The simulation state vector must have all variables
    ///   that are required to compute the stock difference.
    ///
    public func computeStockDelta(_ stock: CompiledStock,
                                  at time: Double,
                                  with state: inout SimulationState) throws -> Double {
        var totalInflow: Double = 0.0
        var totalOutflow: Double = 0.0
        
        // Compute inflow (regardless whether we allow negative)
        //
        for inflow in stock.inflows {
            // TODO: All flows are uni-flows for now. Ignore negative inflows.
            totalInflow += max(state.double(at: inflow), 0)
        }
        
        if stock.allowsNegative {
            for outflow in stock.outflows {
                totalOutflow += state.double(at: outflow)
            }
        }
        else {
            // Compute with a constraint: stock can not be negative
            //
            // We have:
            // - current stock values
            // - expected flow values
            // We need:
            // - get actual flow values based on stock non-negative constraint
            
            // TODO: Add other ways of draining non-negative stocks, not only priority based
            
            // We are looking at a stock, and we know expected inflow and
            // expected outflow. Outflow must be less or equal to the
            // expected inflow plus current state of the stock.
            //
            // Maximum outflow that we can drain from the stock. It is the
            // current value of the stock with aggregate of all inflows.
            //
            var availableOutflow: Double = state.double(at: stock.variableIndex) + totalInflow
            let initialAvailableOutflow: Double = availableOutflow

            for outflow in stock.outflows {
                // Assumed outflow value can not be greater than what we
                // have in the stock. We either take it all or whatever is
                // expected to be drained.
                //
                let actualOutflow = min(availableOutflow,
                                        max(state.double(at: outflow), 0))
                
                totalOutflow += actualOutflow
                // We drain the stock
                availableOutflow -= actualOutflow
                
                // Adjust the flow value to the value actually drained,
                // so we do not fill another stock with something that we
                // did not drain.
                //
                // FIXME: We are changing the current state, we should be changing some "estimated state"
                state[outflow] = Variant(actualOutflow)

                // Sanity check. This should always pass, unless we did
                // something wrong above.
                assert(actualOutflow >= 0.0,
                       "Resulting state must be non-negative")
            }
            // Another sanity check. This should always pass, unless we did
            // something wrong above.
            assert(totalOutflow <= initialAvailableOutflow,
                   "Resulting total outflow must not exceed initial available outflow")

        }
        let delta = totalInflow - totalOutflow
        return delta
    }
    
    /// Comptes differences of stocks.
    ///
    /// - Returns: A state vector that contains difference values for each
    /// stock.
    ///
    public func stockDifference(state current: SimulationState,
                                at time: Double,
                                timeDelta: Double = 1.0) throws -> NumericVector {
        // Get a mutable copy of the state.
        var estimate = current
        
        // 4. Compute stock levels
        //
        var deltaVector = NumericVector(zeroCount: compiledModel.stocks.count)

        for (index, stock) in compiledModel.stocks.enumerated() {
            let delta = try computeStockDelta(stock, at: time, with: &estimate)
            let dtAdjusted = delta * timeDelta
            let newValue = estimate.double(at: stock.variableIndex) + dtAdjusted
            estimate[stock.variableIndex] = Variant(newValue)
            deltaVector[index] = dtAdjusted
        }
        return deltaVector
    }
    
    /// Add stock difference to the simulation state.
    ///
    public func accumulateStocks(_ state: inout SimulationState,
                                 delta: NumericVector) {
        for (stock, stockDelta) in zip(compiledModel.stocks, delta) {
            let value = state.double(at: stock.variableIndex)
            state[stock.variableIndex] = Variant(value + stockDelta)
        }
    }
    
    /// Compute the next state vector.
    ///
    /// - Parameters:
    ///     - time: Time of the computation step.
    ///     - state: Previous state of the computation.
    ///     - timeDelta: Time delta of the computation step.
    ///
    /// - Returns: Computed state vector.
    ///
    /// - Important: Do not call this method directly. Subclasses are
    ///   expected to implement this method.
    ///
    /// - SeeAlso: ``EulerSolver/compute(_:at:timeDelta:)``, ``RungeKutta4Solver/compute(_:at:timeDelta:)``
    /// 
    public func compute(_ state: SimulationState,
                        at time: Double,
                        timeDelta: Double = 1.0) throws -> SimulationState {
        fatalError("Subclasses of Solver are expected to override \(#function)")
    }
}
