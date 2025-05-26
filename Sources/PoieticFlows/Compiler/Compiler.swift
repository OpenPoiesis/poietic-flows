//
//  Compiler.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

// TODO: Add compileExpressions() -> [ObjectID:UnboundExpression], make it independent
// TODO: Add resolvedParameters(...) -> something, make it independent (for auto-connect)
// TODO: Remove checks that are not necessary with ValidatedFrame (safely make them preconditions/fatalErrors)

import PoieticCore


public struct CompilationIssueCollection: Sendable {
    /// Issues specific to particular object.
    public var objectIssues: [ObjectID:[ObjectIssue]]
    
    /// Create an empty design issue collection.
    public init() {
        self.objectIssues = [:]
    }
    
    public var isEmpty: Bool {
        objectIssues.isEmpty
    }
    
    public subscript(id: ObjectID) -> [ObjectIssue]? {
        return objectIssues[id]
    }
    
    /// Append an issue for a specific object.
    public mutating func append(_ issue: ObjectIssue, for id: ObjectID) {
        objectIssues[id, default: []].append(issue)
    }

    public func asDesignIssueCollection() -> DesignIssueCollection {
        var result: DesignIssueCollection = DesignIssueCollection()

        for (id, errors) in objectIssues {
            for error in errors {
                result.append(error.asDesignIssue(), for: id)
            }
        }
        return result
    }
}

/// Error thrown by the compiler during compilation.
///
/// The only relevant case is ``hasIssues``, any other case means a programming error.
///
/// After catching the ``hasIssues`` error, the caller might get the issues from
/// the compiler and propagate them to the user.
///
public enum CompilerError: Error {
    /// Object has issues, they were added to the list of issues.
    ///
    /// This error means that the input frame has user issues. The caller should
    /// get the issues from the compiler.
    ///
    /// This is the only error that is relevant. Any other error means
    /// that something failed internally.
    ///
    case issues(CompilationIssueCollection)
    
    /// Error caused by some internal functioning. This error typically means something was not
    /// correctly validated either within the library or by an application. The internal error
    /// is not caused by the user.
    case internalError(InternalCompilerError)
}

/// Error caused by some compiler internals, not by the user.
///
/// This error should not be displayed to the user fully, only as a debug information or as an
/// information provided to the developers by the user.
///
public enum InternalCompilerError: Error, Equatable {
    /// Error thrown during compilation that should be captured by the compiler.
    ///
    /// Used to indicate that the compilation might continue to collect more errors, but must
    /// result in an error at the end.
    ///
    /// This error should never escape the compiler.
    ///
    case objectIssue
    
    /// Attribute is missing or attribute type is mismatched. This error means
    /// that the frame is not valid according to the ``FlowsMetamodel``.
    case attributeExpectationFailure(ObjectID, String)
    
    /// Formula compilation failed in an unexpected way.
    case formulaCompilationFailure(ObjectID)
    
    // Invalid Frame Error - validation on the caller side failed
    case structureTypeMismatch(ObjectID)
    case objectNotFound(ObjectID)
}

/// An object that compiles the model into an internal representation called Compiled Model.
///
/// The design represents an idea or a creation of a user in a form that
/// is closest to the user. To perform a simulation we need a different form
/// that can be interpreted by a machine.
///
/// The purpose of the compiler is to validate the design and
/// translate it into an internal representation.
///
/// - SeeAlso: ``compile()``, ``SimulationPlan``
///
public class Compiler {
    /// The frame containing the design to be compiled.
    ///
    /// The frame must be valid according to the ``FlowsMetamodel``.
    ///
    public let frame: ValidatedFrame
    
    /// Flows domain view of the frame.
    public let view: StockFlowView
    
    // MARK: - Compiler State
    // -----------------------------------------------------------------
    
    /// Issues of the object gathered during compilation.
    ///
    public var issues: CompilationIssueCollection
    
    /// List of objects in an order of computational dependency.
    ///
    public private(set) var orderedObjects: [ObjectSnapshot]
    
    /// List of simulation objects that will be included in the simulation plan.
    ///
    /// - SeeAlso: ``SimulationPlan/simulationObjects``
    ///
    public private(set) var simulationObjects: [SimulationObject] = []
    public private(set) var flows: [BoundFlow] = []
    
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
    public private(set) var stateVariables: [StateVariable]
    
    /// Mapping between object ID and index of its corresponding simulation
    /// variable.
    ///
    /// Used in compilation of simulation nodes.
    ///
    internal var objectVariableIndex: [ObjectID: Int]
    
    /// Mapping between a variable name and a bound variable reference.
    ///
    /// Used in binding of arithmetic expressions.
    internal var nameIndex: [String:SimulationState.Index]
    
    internal var parsedExpressions: [ObjectID:UnboundExpression]
    
    /// List of built-in variable names, fetched from the metamodel.
    ///
    /// Used in binding of arithmetic expressions.
    private var builtinVariableNames: [String]
    
    /// List of built-in functions.
    ///
    /// Used in binding of arithmetic expressions.
    ///
    /// - SeeAlso: ``compileFormulaObject(_:)``
    ///
    internal let functions: [String: Function]
    
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
    
    // - MARK: Compilation
    /// Compiles the design and returns compiled model that can be simulated.
    ///
    /// The compilation process is as follows:
    ///
    /// 1. Collect simulation nodes and order them by computation dependency.
    /// 2. Create a name-to-object map and check for potential name duplicates.
    /// 3. Compile all formulas (expressions) and bind them with concrete
    ///    objects.
    /// 4. Prepare built-in variables and allocate them in the simulation state.
    /// 5. Compile individual objects based on the object type:
    ///     - objects with `Formula` component
    ///     - graphical functions
    ///     - delay and smooth
    /// 6. Compile stocks and flows.
    /// 7. Compile non-computational objects: charts, bindings.
    /// 8. Fetch simulation defaults.
    /// 9. Create a compiled model.
    ///
    /// - Returns: A ``StockFlowModel`` that can be used directly by the
    ///   simulator.
    /// - Throws: A ``CompilerError`` when there are issues with the model
    ///   that are caused by the user.
    ///
    /// - Note: The compilation is trying to gather as many errors as possible.
    ///   It does not fail in the first error encountered unless the error
    ///   might prevent from other steps to be executed.
    ///
    /// - SeeAlso: ``Simulator/init(_:simulation:)``
    ///
    public func compile() throws (CompilerError) -> SimulationPlan {
        issues = CompilationIssueCollection()

        try collectAndSortObjects()
        let builtins = prepareBuiltins()

        do {
            try parseExpressions()
        }
        catch {
            throw .internalError(error)
        }
        try validateFormulaParameterConnections()
        
        // 1. Compile flows (stocks require them)
        // 2. Compile stocks
        // 3. Compile auxiliaries (everything else)
        
        for object in self.orderedObjects {
            do {
                try self.compileObject(object)
            }
            catch .objectIssue {
                continue
            }
            catch {
                throw .internalError(error)
            }
        }
        
        guard issues.isEmpty else { throw .issues(issues) }
        
        let stocks: [BoundStock]
        do {
            stocks = try compileStocks()
        }
        catch .objectIssue {
            throw .issues(issues)
        }
        catch {
            throw .internalError(error)
        }
        let bindings = try compileControlBindings()
        let defaults = try compileDefaults()
        let charts = try compileCharts()
        
        guard let timeIndex = nameIndex["time"] else {
            fatalError("No time variable within the builtins")
        }
        
        return SimulationPlan(
            simulationObjects: self.simulationObjects,
            stateVariables: self.stateVariables,
            builtins: builtins,
            timeVariableIndex: timeIndex,
            stocks: stocks,
            flows: self.flows,
            charts: charts,
            valueBindings: bindings,
            simulationParameters: defaults
        )
    }
   
    func collectAndSortObjects() throws (CompilerError) {
        let unorderedNodes = view.simulationNodes
        var homonyms: [String: [ObjectID]] = [:]
        
        // 1. Collect nodes relevant to the simulation
        for node in unorderedNodes {
            guard let name = node.name else {
                throw .internalError(.attributeExpectationFailure(node.objectID, "name"))
            }
            if name.isEmpty || name.allSatisfy({ $0.isWhitespace}){
                issues.append(.emptyName, for: node.objectID)
            }
            homonyms[name, default: []].append(node.objectID)
        }
        
        var dupes: [String] = []
        
        for (name, ids) in homonyms where ids.count > 1 {
            let issue = ObjectIssue.duplicateName(name)
            dupes.append(name)
            for id in ids {
                issues.append(issue, for: id)
            }
        }
    
        // 2. Sort nodes based on computation dependency.
        let parameterEdges:[EdgeObject] = frame.edges.filter {
            $0.object.type === ObjectType.Parameter
        }

        let parameterDependency = Graph(nodes: unorderedNodes.map { $0.objectID },
                                        edges: parameterEdges)
        
        guard let ordered = parameterDependency.topologicalSort() else {
            let cycleEdges = parameterDependency.cycles()
            var nodes: Set<ObjectID> = Set()
            
            for edge in cycleEdges {
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                issues.append(.computationCycle, for: edge.key)
            }
            for node in nodes {
                issues.append(.computationCycle, for: node)
            }
            throw .issues(issues)
        }
        
        guard issues.isEmpty else { throw .issues(issues) }
        
        self.orderedObjects = ordered.map { frame.object($0) }
    }
    
    /// Prepare built-in variables.
    ///
    /// For each builtin from the ``BuiltinVariable`` a state variable is allocated. Newly allocated
    /// indices are included in the ``nameIndex``.
    ///
    /// All variable names are extracted to be used in the ``compileFormulaObject()``.
    ///
    /// - SeeAlso: ``StockFlowSimulation/updateBuiltins(_:)``
    ///
    func prepareBuiltins() -> BoundBuiltins {
        let builtins = BoundBuiltins(
            step: createStateVariable(builtin: .step),
            time: createStateVariable(builtin: .time),
            timeDelta: createStateVariable(builtin: .timeDelta)
        )
        
        self.nameIndex[BuiltinVariable.time.name] = builtins.time
        self.nameIndex[BuiltinVariable.timeDelta.name] = builtins.timeDelta
        self.nameIndex[BuiltinVariable.step.name] = builtins.step
        
        // Extract builtin variable names to be used in compileFormulaObject()
        self.builtinVariableNames = BuiltinVariable.allCases.map { $0.name }
        
        return builtins
    }
    
    /// Compile a simulation node.
    ///
    /// The function compiles a node that represents a variable or a kind of
    /// computation.
    ///
    /// The following types of nodes are considered:
    /// - a node with a ``/PoieticCore/Trait/Formula``, compiled as a formula.
    /// - a node with a ``/PoieticCore/Trait/GraphicalFunction``, compiled as a graphical
    ///   function.
    ///
    /// - Returns: a computational representation of the simulation node.
    ///
    /// - Throws: ``NodeIssuesError`` with list of issues for the node.
    /// - SeeAlso: ``compileFormulaNode(_:)``, ``compileGraphicalFunctionNode(_:)``.
    ///
    func compileObject(_ object: ObjectSnapshot) throws (InternalCompilerError) {
        let role: SimulationObject.Role
        let rep: ComputationalRepresentation

        if object.type.hasTrait(Trait.Formula) {
            rep = try compileFormulaObject(object)
        }
        else if object.type.hasTrait(Trait.GraphicalFunction) {
            rep = try compileGraphicalFunctionNode(object)
        }
        else if object.type.hasTrait(Trait.Delay) {
            rep = try compileDelayNode(object)
        }
        else if object.type.hasTrait(Trait.Smooth) {
            rep = try compileSmoothNode(object)
        }
        else {
            // Hint: If this error happens, then check one of the the following:
            // - the condition in the stock-flows view method returning
            //   simulation nodes
            // - whether the object design constraints work properly
            // - whether the object design metamodel is stock-flows metamodel
            //   and that it has necessary components
            //
            fatalError("Unknown simulation object type \(object.type.name), object: \(object.objectID)")
        }
        
        // TODO: We must have name here already, this is redundant fetching
        guard let name = object.name else {
            throw .attributeExpectationFailure(object.objectID, "name")
        }
        
        let index = createStateVariable(content: .object(object.objectID),
                                        valueType: rep.valueType,
                                        name: name)
        self.objectVariableIndex[object.objectID] = index
        self.nameIndex[name] = index

        if object.type === ObjectType.Stock {
            role = .stock
        }
        else if object.type === ObjectType.FlowRate {
            role = .flow
            let flow = try compileFlow(object,
                                       name: name,
                                       valueType: rep.valueType)
            self.flows.append(flow)
        }
        else if object.type.hasTrait(Trait.Auxiliary) {
            role = .auxiliary
        }
        else {
            // Hint: If this error happens, then check the following:
            // - stock-flow metamodel and its validation
            // - method collectAndSortObjects()
            // - view.simulationNodes
            fatalError("Unknown simulation object role for object type: \(object.type.name)")
        }
        
        
        let sim = SimulationObject(objectID: object.objectID,
                                   computation: rep,
                                   variableIndex: index,
                                   role: role,
                                   valueType: rep.valueType,
                                   name: name)
   
        
        self.simulationObjects.append(sim)
    }
    
    /// Validates parameter of a node.
    ///
    /// The method checks whether the following two requirements are met:
    ///
    /// - node using a parameter name in an expression must have a
    ///   ``/PoieticCore/ObjectType/Parameter`` edge from the parameter node
    ///   with given name.
    /// - node must _not_ have a ``/PoieticCore/ObjectType/Parameter``connection from
    ///   a node if the expression is not referring to that node.
    ///
    /// If any of the two requirements are not met, then a corresponding
    /// type of ``ObjectIssue`` is added to the list of issues.
    ///
    /// - Throws: Compiler error with ``ObjectIssue/unknownParameter(_:)`` or
    ///   ``ObjectIssue/unusedInput(_:)`` assigned to each offending object.
    ///
    public func validateFormulaParameterConnections() throws (CompilerError) {
        var hasIssues: Bool = false
        
        // Edges into formula objects
        let parameterEdges = frame.filterEdges {
            $0.object.type === ObjectType.Parameter
            && $0.targetObject.type.hasTrait(Trait.Formula)
        }
        
        var required: [ObjectID:Set<String>] = [:]
        var unused: [ObjectID:[EdgeObject]] = [:]

        for (id, expression) in parsedExpressions {
            let vars = expression.allVariables.filter { !builtinVariableNames.contains($0) }
            required[id] = Set(vars)
        }
        
        for edge in parameterEdges {
            guard let parameter = edge.originObject.name else {
                throw .internalError(.attributeExpectationFailure(edge.key, "name"))
            }
            if let existing = required[edge.target], existing.contains(parameter) {
                required[edge.target]!.remove(parameter)
            }
            else {
                unused[edge.target, default: []].append(edge)
            }
        }
        
        for (id, params) in required {
            for name in params {
                issues.append(.unknownParameter(name), for: id)
                hasIssues = true
            }
        }

        for (id, edges) in unused {
            for edge in edges {
                issues.append(.unusedInput(edge.originObject.name!), for: id)
                hasIssues = true
            }
        }

        guard !hasIssues else {
            throw .issues(issues)
        }
    }

    
    func compileCharts() throws (CompilerError) -> [Chart] {
        let nodes = frame.filter { $0.type === ObjectType.Chart }
        
        var charts: [PoieticFlows.Chart] = []
        for node in nodes {
            let edges = frame.filterEdges {
                $0.object.type === ObjectType.ChartSeries
            }
            
            let series = edges.map { $0.targetObject }
            let chart = PoieticFlows.Chart(node: node,
                                           series: series)
            charts.append(chart)
        }
        return charts
    }
    
    // TODO: [WIP] This requires attention, too much going on in the filter
    public func compileControlBindings() throws (CompilerError) -> [CompiledControlBinding] {
        var bindings: [CompiledControlBinding] = []
        for object in frame.filter(type: ObjectType.ValueBinding) {
            guard let edge = EdgeObject(object, in: frame) else {
                throw .internalError(.structureTypeMismatch(object.objectID))
            }
            
            guard let index = objectVariableIndex[edge.target] else {
                throw .internalError(.objectNotFound(edge.target))
            }
            let binding = CompiledControlBinding(control: edge.origin,
                                                 variableIndex: index)
            bindings.append(binding)
        }
        return bindings
    }
    
    // TODO: Rename to compileSimulationParameters
    public func compileDefaults() throws (CompilerError) -> SimulationParameters? {
        guard let simInfo = frame.first(trait: Trait.Simulation) else {
            return nil
        }
        return SimulationParameters(fromObject: simInfo)
    }
    
    /// Creates a state variable.
    ///
    /// - Parameters:
    ///     - content: Content of the state variable – either an object or a
    ///       builtin.
    ///       See ``StateVariable/Content`` for more information.
    ///     - valueType: Type of the state variable value.
    ///     - name: Name of the state variable.
    ///
    public func createStateVariable(content: StateVariable.Content,
                                    valueType: ValueType,
                                    name: String) -> SimulationState.Index {
        // Note: Consider renaming this method to "allocate..."
        let variableIndex = stateVariables.count
        let variable = StateVariable(index: variableIndex,
                                     content: content,
                                     valueType: valueType,
                                     name: name)
        stateVariables.append(variable)
        
        if case let .object(id) = content {
            objectVariableIndex[id] = variableIndex
        }
        
        return variableIndex
    }
    
    /// Convenience method that creates a state variable for a built-in.
    ///
    func createStateVariable(builtin: BuiltinVariable) -> SimulationState.Index {
        return createStateVariable(content: .builtin(builtin),
                                   valueType: builtin.valueType,
                                   name: builtin.name)
    }
}
