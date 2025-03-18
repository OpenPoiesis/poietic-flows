//
//  Compiler.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

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
    case intermediateError
    
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
    public let view: StockFlowView<ValidatedFrame>
    
    // MARK: - Compiler State
    // -----------------------------------------------------------------
    
    /// Issues of the object gathered during compilation.
    ///
    public var issues: CompilationIssueCollection
    
    /// List of objects in an order of computational dependency.
    ///
    public private(set) var orderedObjects: [DesignObject]
    
    /// List of simulation objects that will be included in the simulation plan.
    ///
    /// - SeeAlso: ``SimulationPlan/simulationObjects``
    ///
    public private(set) var simulationObjects: [SimulationObject] = []
    
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
    private var nameIndex: [String:SimulationState.Index]
    
    private var parsedExpressions: [ObjectID:UnboundExpression]
    
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
    private let functions: [String: Function]
    
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
        try initialize()
        let builtins = try prepareBuiltins()
        try parseExpressions()
        try validateFormulaParameterConnections()
        
        var intermediateError: Bool = false
        
        for object in self.orderedObjects {
            do {
                try self.compile(object)
            }
            catch .internalError(.intermediateError) {
                intermediateError = true
                continue
            }
        }
        
        guard issues.isEmpty && !intermediateError else {
            throw .issues(issues)
        }
        
        let stocks = try compileStocksAndFlows()
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
            charts: charts,
            valueBindings: bindings,
            simulationParameters: defaults
        )
    }
    
    /// - Precondition: Simulation nodes must have a name
    ///
    func initialize() throws (CompilerError) {
        issues = CompilationIssueCollection()
        
        let unorderedSimulationNodes = view.simulationNodes
        var homonyms: [String: [ObjectID]] = [:]
        
        // 1. Collect nodes relevant to the simulation
        for node in unorderedSimulationNodes {
            guard let name = node.name else {
                throw .internalError(.attributeExpectationFailure(node.id, "name"))
            }
            homonyms[name, default: []].append(node.id)
        }
        
        // 2. Sort nodes based on computation dependency.
        let parameterEdges:[EdgeObject] = frame.filterEdges {
            $0.object.type === ObjectType.Parameter
        }
        let parameterDependency = Graph(nodes: unorderedSimulationNodes,
                                        edges: parameterEdges)
        
        guard let ordered = parameterDependency.topologicalSort() else {
            let cycleEdges = parameterDependency.cycles()
            var nodes: Set<ObjectID> = Set()
            
            for edge in cycleEdges {
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                issues.append(.computationCycle, for: edge.id)
            }
            for node in nodes {
                issues.append(.computationCycle, for: node)
            }
            throw .issues(issues)
        }
        
        // 3. Report the duplicates, if any
        
        var dupes: [String] = []
        
        for (name, ids) in homonyms where ids.count > 1 {
            let issue = ObjectIssue.duplicateName(name)
            dupes.append(name)
            for id in ids {
                issues.append(issue, for: id)
            }
        }
        
        guard issues.isEmpty else {
            throw .issues(issues)
        }
        
        self.orderedObjects = ordered.map { frame.object($0) }
    }
    
    func parseExpressions() throws (CompilerError) {
        parsedExpressions = [:]
        
        for object in orderedObjects {
            guard object.type.hasTrait(.Formula) else {
                continue
            }
            
            guard let formula = try? object["formula"]?.stringValue() else {
                throw .internalError(.attributeExpectationFailure(object.id, "formula"))
            }
            
            let parser = ExpressionParser(string: formula)
            let expr: UnboundExpression
            
            do {
                expr = try parser.parse()
            }
            catch {
                issues.append(.expressionSyntaxError(error), for: object.id)
                continue
            }
            
            parsedExpressions[object.id] = expr
        }
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
    func prepareBuiltins() throws (CompilerError) -> CompiledBuiltinState {
        let builtins = CompiledBuiltinState(
            time: createStateVariable(builtin: .time),
            timeDelta: createStateVariable(builtin: .timeDelta),
            step: createStateVariable(builtin: .step)
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
    func compile(_ object: DesignObject) throws (CompilerError) {
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
            fatalError("Unknown simulation object type \(object.type.name), object: \(object.id)")
        }
        
        guard let name = object.name else {
            throw .internalError(.attributeExpectationFailure(object.id, "name"))
        }
        
        // Determine simulation type
        //
        let simType: SimulationObject.SimulationObjectType
        if object.type === ObjectType.Stock {
            simType = .stock
        }
        else if object.type === ObjectType.FlowRate {
            simType = .flow
        }
        else if object.type.hasTrait(Trait.Auxiliary) {
            simType = .auxiliary
        }
        else {
            fatalError("Unknown simulation node type: \(object.type.name)")
        }
        
        let index = createStateVariable(content: .object(object.id),
                                        valueType: rep.valueType,
                                        name: name)
        self.objectVariableIndex[object.id] = index
        self.nameIndex[name] = index
        
        let sim = SimulationObject(id: object.id,
                                   type: simType,
                                   variableIndex: index,
                                   valueType: rep.valueType,
                                   computation: rep,
                                   name: name)
        
        self.simulationObjects.append(sim)
    }
    
    /// Compile a node containing a formula.
    ///
    /// For each node with an arithmetic expression the expression is parsed
    /// from a text into an internal representation. The variable and function
    /// names are resolved to point to actual entities and a new bound
    /// expression is formed.
    ///
    /// - Returns: Computational representation wrapping a formula.
    ///
    /// - Parameters:
    ///     - node: node containing already parsed formula in
    ///       ``ParsedFormulaComponent``.
    ///
    /// - Precondition: The node must have ``ParsedFormulaComponent`` associated
    ///   with it.
    ///
    /// - Throws: ``NodeIssueError`` if there is an issue with parameters,
    ///   function names or other variable names in the expression.
    ///
    func compileFormulaObject(_ object: DesignObject) throws (CompilerError) -> ComputationalRepresentation {
        guard let unboundExpression = parsedExpressions[object.id] else {
            if issues[object.id] != nil {
                // Compilation already has issues, we just proceed to collect some more.
                throw .internalError(.intermediateError)
            }
            else {
                throw .internalError(.formulaCompilationFailure(object.id))
            }
        }
        
        // Finally bind the expression.
        //
        let boundExpression: BoundExpression
        do {
            boundExpression = try bindExpression(unboundExpression,
                                                 variables: stateVariables,
                                                 names: nameIndex,
                                                 functions: functions)
        }
        catch /* ExpressionError */ {
            issues.append(.expressionError(error), for: object.id)
            throw .issues(issues)
        }
        
        return .formula(boundExpression)
    }
    
    /// Compiles a graphical function.
    ///
    /// This method creates a ``/PoieticCore/Function`` object with a single argument and a
    /// numeric return value. The function will compute the output based on the
    /// input parameter and on specifics of the graphical function points
    /// interpolation.
    ///
    /// - Requires: node
    /// - Throws: ``NodeIssue`` if the function parameter is not connected.
    ///
    /// - SeeAlso: ``CompiledGraphicalFunction``, ``Solver/evaluate(objectAt:with:)``
    ///
    func compileGraphicalFunctionNode(_ object: DesignObject) throws (CompilerError) -> ComputationalRepresentation{
        guard let points = try? object["graphical_function_points"]?.pointArray() else {
            throw .internalError(.attributeExpectationFailure(object.id, "graphical_function_points"))
        }
        // TODO: Interpolation method
        let function = GraphicalFunction(points: points)
        
        let parameters = view.incomingParameterNodes(object.id)
        guard let parameterNode = parameters.first else {
            issues.append(ObjectIssue.missingRequiredParameter, for: object.id)
            throw .issues(issues)
        }
        
        let boundFunc = BoundGraphicalFunction(function: function,
                                               parameterIndex: objectVariableIndex[parameterNode.id]!)
        return .graphicalFunction(boundFunc)
    }
    
    /// Compile a delay node.
    ///
    func compileDelayNode(_ object: DesignObject) throws (CompilerError) -> ComputationalRepresentation{
        let queueIndex = createStateVariable(content: .internalState(object.id),
                                             valueType: .doubles,
                                             name: "delay_queue_\(object.id)")
        
        let initialValueIndex = createStateVariable(content: .internalState(object.id),
                                                    valueType: .doubles,
                                                    name: "delay_init_\(object.id)")
        
        let parameters = view.incomingParameterNodes(object.id)
        guard let parameterNode = parameters.first else {
            issues.append(ObjectIssue.missingRequiredParameter, for: object.id)
            throw .issues(issues)
        }
        
        let parameterIndex = objectVariableIndex[parameterNode.id]!
        let variable = stateVariables[parameterIndex]
        
        guard let duration = try? object["delay_duration"]?.intValue() else {
            throw .internalError(.attributeExpectationFailure(object.id, "delay_duration"))
        }
        
        let initialValue = object["initial_value"]
        
        guard case let .atom(atomType) = variable.valueType else {
            issues.append(.unsupportedDelayValueType(variable.valueType), for: object.id)
            throw .issues(issues)
        }
        
        // TODO: Check whether the initial value and variable.valueType are the same
        let compiled = BoundDelay(
            steps: duration,
            initialValue: initialValue,
            valueType: atomType,
            initialValueIndex: initialValueIndex,
            queueIndex: queueIndex,
            inputValueIndex: parameterIndex
        )
        
        return .delay(compiled)
    }
    
    /// Compile a value smoothing node.
    ///
    func compileSmoothNode(_ object: DesignObject) throws (CompilerError) -> ComputationalRepresentation{
        let smoothValueIndex = createStateVariable(content: .internalState(object.id),
                                                   valueType: .doubles,
                                                   name: "smooth_value_\(object.id)")
        
        let parameters = view.incomingParameterNodes(object.id)
        guard let parameterNode = parameters.first else {
            issues.append(ObjectIssue.missingRequiredParameter, for: object.id)
            throw .issues(issues)
        }
        
        let parameterIndex = objectVariableIndex[parameterNode.id]!
        let variable = stateVariables[parameterIndex]
        
        guard let windowTime = try? object["window_time"]?.doubleValue() else {
            throw .internalError(.attributeExpectationFailure(object.id, "window_time"))
        }
        
        guard case .atom(_) = variable.valueType else {
            issues.append(.unsupportedDelayValueType(variable.valueType), for: object.id)
            throw .issues(issues)
        }
        
        let compiled = BoundSmooth(
            windowTime: windowTime,
            smoothValueIndex: smoothValueIndex,
            inputValueIndex: parameterIndex
        )
        
        return .smooth(compiled)
    }
    
    /// Compile all stock nodes.
    ///
    /// The function extracts component from the stock that is necessary
    /// for simulation. Then the function collects all inflows and outflows
    /// of the stock.
    ///
    /// - Returns: Extracted and derived stock node information.
    ///
    func compileStocksAndFlows() throws (CompilerError) -> [BoundStock] {
        let stocks = simulationObjects.filter { $0.type == .stock }
        let flows = simulationObjects.filter { $0.type == .flow }.compactMap { frame[$0.id] }
        
        var flowPriorities: [ObjectID:Int] = [:]
        var outflows: [ObjectID: [ObjectID]] = [:]
        var inflows: [ObjectID: [ObjectID]] = [:]
        
        // This step is needed for proper computation of non-negative stocks
        // Stock adjacencies without delayed input - break the cycle at stocks
        // with delayed_input=true.
        let adjacencies = view.stockAdjacencies().filter { !$0.targetHasDelayedInflow }
        let adjacencySubgraph = Graph(nodes: stocks, edges: adjacencies)
        
        guard let sorted = adjacencySubgraph.topologicalSort() else {
            let cycleEdges = adjacencySubgraph.cycles()
            var nodes: Set<ObjectID> = Set()
            
            for edge in cycleEdges {
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                issues.append(.flowCycle, for: edge.id)
            }
            for node in nodes {
                issues.append(ObjectIssue.flowCycle, for: node)
            }
            throw .issues(issues)
        }
        
        let sortedStocks = sorted.map { frame.object($0) }
        
        for edge in view.flowEdges {
            if edge.originObject.type === ObjectType.Stock && edge.targetObject.type === ObjectType.FlowRate {
                outflows[edge.origin, default: []].append(edge.target)
            }
            else if edge.originObject.type === ObjectType.FlowRate && edge.targetObject.type === ObjectType.Stock {
                inflows[edge.target, default: []].append(edge.origin)
            }
            else {
                fatalError("Compiler error: Flow edge endpoints constraint violated")
            }
        }
        
        // Sort the outflows by priority
        for flow in flows {
            guard let priority = try? flow["priority"]?.intValue() else {
                throw .internalError(.attributeExpectationFailure(flow.id, "priority"))
            }
            flowPriorities[flow.id] = priority
        }
        
        for stock in sortedStocks {
            if let unsorted = outflows[stock.id] {
                let items = unsorted.map { (id: $0, priority: flowPriorities[$0]!) }
                let sorted = items.sorted { $0.priority < $1.priority }
                outflows[stock.id] = sorted.map { $0.id }
            }
            else {
                outflows[stock.id] = []
            }
        }
        
        var result: [BoundStock] = []
        
        for object in sortedStocks {
            let inflowIndices = inflows[object.id]?.map { objectVariableIndex[$0]! } ?? []
            let outflowIndices = outflows[object.id]?.map { objectVariableIndex[$0]! } ?? []
            
            // We can `try!` and force unwrap, because here we already assume
            // the model was validated
            let allowsNegative = try! object["allows_negative"]!.boolValue()
            let delayedInflow = try! object["delayed_inflow"]!.boolValue()
            
            let compiled = BoundStock(
                id: object.id,
                variableIndex: objectVariableIndex[object.id]!,
                allowsNegative: allowsNegative,
                delayedInflow: delayedInflow,
                inflows: inflowIndices,
                outflows: outflowIndices
            )
            result.append(compiled)
        }
        
        return result
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
                throw .internalError(.attributeExpectationFailure(edge.id, "name"))
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
            let hood = frame.hood(node.id, direction: .outgoing) {
                $0.object.type === ObjectType.ChartSeries
            }
            
            let series = hood.nodes.map { $0 }
            let chart = PoieticFlows.Chart(node: node,
                                           series: series)
            charts.append(chart)
        }
        return charts
    }
    
    public func compileControlBindings() throws (CompilerError) -> [CompiledControlBinding] {
        var bindings: [CompiledControlBinding] = []
        for object in frame.filter(type: ObjectType.ValueBinding) {
            guard let edge = EdgeObject(object, in: frame) else {
                throw .internalError(.structureTypeMismatch(object.id))
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
