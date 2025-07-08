//
//  CompilationContext.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 12/06/2025.
//

import PoieticCore

public class CompilationContext {
    /// The frame containing the design to be compiled.
    ///
    /// The frame must be valid according to the ``FlowsMetamodel``.
    ///
    public let frame: ValidatedFrame
    
    /// Flows domain view of the frame.
    public let view: StockFlowView
    
    /// Issues of the object gathered during compilation.
    ///
    public var issues: CompilationIssueCollection
    
    /// List of objects in an order of computational dependency.
    ///
    public var orderedObjects: [ObjectSnapshot]
    
    /// List of simulation objects that will be included in the simulation plan.
    ///
    /// - SeeAlso: ``SimulationPlan/simulationObjects``
    ///
    public var simulationObjects: [SimulationObject] = []
    public var flows: [BoundFlow] = []
    
    /// List of simulation state variables.
    ///
    /// The list of state variables contain values of builtins, values of
    /// nodes and values of internal states.
    ///
    /// Each node is typically assigned one state variable which represents
    /// the node's value at given state. Some nodes might contain internal
    /// state that might be present in multiple state variables.
    ///
    /// The internal state is typically not user-presentable and is a state
    /// associated with stateful functions or other computation objects.
    ///
    /// The state variables are added to the list using
    /// ``createStateVariable(content:valueType:name:)``, which allocates a variable
    /// and sets other associated mappings depending on the variable content
    /// type.
    ///
    /// - SeeAlso: ``SimulationPlan/stateVariables``,
    ///   ``createStateVariable(content:valueType:name:)``
    ///
    public var stateVariables: [StateVariable]
    
    /// Mapping between object ID and index of its corresponding simulation
    /// variable.
    ///
    /// Used in compilation of simulation nodes.
    ///
    internal var objectVariableIndex: [ObjectID: SimulationState.Index]
    
    /// Mapping between a variable name and a bound variable reference.
    ///
    /// Used in binding of arithmetic expressions.
    internal var nameIndex: [String:SimulationState.Index]
    
    internal var parsedExpressions: [ObjectID:UnboundExpression]
    
    /// List of built-in variable names, fetched from the metamodel.
    ///
    /// Used in binding of arithmetic expressions.
    internal var builtinVariableNames: [String]
    
    /// List of built-in functions.
    ///
    /// Used in binding of arithmetic expressions.
    ///
    /// - SeeAlso: ``compileFormulaObject(_:)``
    ///
    internal let functions: [String: Function]
    
    // MARK: - Compilation Results
    // -----------------------------------------------------------------
    
    /// Compiled built-in variables ready for the simulation plan.
    public var builtins: BoundBuiltins?
    
    /// Compiled stocks ready for the simulation plan.
    public var stocks: [BoundStock] = []
    
    /// Compiled control bindings ready for the simulation plan.
    public var bindings: [CompiledControlBinding] = []
    
    /// Compiled simulation parameters ready for the simulation plan.
    public var defaults: SimulationParameters?
    
    /// Compiled charts ready for the simulation plan.
    public var charts: [Chart] = []
    
    /// Create a new compiler for a given frame.
    ///
    /// The frame must be validated using the ``FlowsMetamodel``.
    ///
    public init(frame: ValidatedFrame) {
        self.frame = frame
        self.view = StockFlowView(frame)
        
        // Notes:
        // - It might be desired in the future to cache parsedExpressions in some cases
        
        orderedObjects = []
        stateVariables = []
        builtinVariableNames = []
        parsedExpressions = [:]
        nameIndex = [:]
        objectVariableIndex = [:]
        issues = CompilationIssueCollection()
        
        var functions:[String:Function] = [:]
        for function in Function.AllBuiltinFunctions {
            functions[function.name] = function
        }
        self.functions = functions
    }
}
