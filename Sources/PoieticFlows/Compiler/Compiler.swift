//
//  Compiler.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

import PoieticCore


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
    case hasIssues

    /// Attribute is missing or attribute type is mismatched. This error means
    /// that the frame is not valid according to the ``FlowsMetamodel``.
    case attributeExpectationFailure(ObjectID, String)

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
/// - SeeAlso: ``compile()``, ``CompiledModel``
///
public class Compiler {
    /// The frame containing the design to be compiled.
    ///
    /// The frame must be valid according to the ``FlowsMetamodel``.
    ///
    public let frame: DesignFrame
    
    /// Flows domain view of the frame.
    public let view: StockFlowView<DesignFrame>

    // MARK: - Compiler State
    // -----------------------------------------------------------------

    private var orderedObjects: [DesignObject]

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
    /// - SeeAlso: ``CompiledModel/stateVariables``,
    ///   ``createStateVariable(content:valueType:name:)``
    ///
    public private(set) var stateVariables: [StateVariable]


    /// Issues of the object gathered during compilation.
    ///
    public var issues: [ObjectID: [ObjectIssue]]

    /// List of built-in functions.
    ///
    /// Used in binding of arithmetic expressions.
    ///
    /// - SeeAlso: ``compileFormulaObject(_:)``
    ///
    private let functions: [String: Function]

    /// List of built-in variable names, fetched from the metamodel.
    ///
    /// Used in binding of arithmetic expressions.
    private var builtinVariableNames: [String]

    /// Mapping between a variable name and a bound variable reference.
    ///
    /// Used in binding of arithmetic expressions.
    private var nameIndex: [String:SimulationState.Index]
    
    private var parsedExpressions: [ObjectID:UnboundExpression]

    /// Mapping between object ID and index of its corresponding simulation
    /// variable.
    ///
    /// Used in compilation of simulation nodes.
    ///
    internal var objectVariableIndex: [ObjectID: Int]


    // OUTPUT
    private var simulationObjects: [SimulationObject] = []
    
    var compiledStocks: [CompiledStock] = []

    /// Appends an error to the list of of node issues
    ///
    func appendIssue(_ error: ObjectIssue, for id: ObjectID) {
        issues[id, default:[]].append(error)
    }
    
    /// Append a list of issues to an object.
    ///
    func appendIssues(_ errors: [ObjectIssue], for id: ObjectID) {
        issues[id, default:[]] += errors
    }
    
    /// Flag whether the compiler has encountered any issues.
    ///
    public var hasIssues: Bool {
        return issues.values.contains { !$0.isEmpty }
    }


    /// Create a new compiler for a given frame.
    ///
    /// The frame must be validated using the ``FlowsMetamodel``.
    ///
    public init(frame: DesignFrame) {
        self.frame = frame
        self.view = StockFlowView(frame)
        
        // Notes:
        // - It might be desired in the future to cache parsedExpressions in some cases

        orderedObjects = []
        stateVariables = []
        builtinVariableNames = []
        issues = [:]
        parsedExpressions = [:]
        nameIndex = [:]
        objectVariableIndex = [:]

        var functions:[String:Function] = [:]
        for function in AllBuiltinFunctions {
            functions[function.name] = function
        }
        self.functions = functions
    }

    // - MARK: State Queries
    /// Get a list of issues for given object.
    ///
    public func issues(for id: ObjectID) -> [ObjectIssue] {
        return issues[id] ?? []
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
    /// - Returns: A ``CompiledModel`` that can be used directly by the
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
    public func compile() throws (CompilerError) -> CompiledModel {
        try initialize()
        let builtins = try prepareBuiltins()
        try parseExpressions()
        
        for object in self.orderedObjects {
            try self.compile(object)
        }
        
        if hasIssues {
            throw .hasIssues
        }

        try compileStocksAndFlows()
        let bindings = try compileControlBindings()
        let defaults = try compileDefaults()
        let charts = try compileCharts()
        
        guard let timeIndex = nameIndex["time"] else {
            fatalError("No time variable within the builtins")
        }

        return CompiledModel(
            simulationObjects: self.simulationObjects,
            stateVariables: self.stateVariables,
            builtins: builtins,
            timeVariableIndex: timeIndex,
            stocks: self.compiledStocks,
            charts: charts,
            valueBindings: bindings,
            simulationDefaults: defaults
        )
    }
    
    /// - Precondition: Simulation nodes must have a name
    ///
    func initialize() throws (CompilerError) {
        issues = [:]
        
        let unorderedSimulationNodes = view.simulationNodes
        var homonyms: [String: [ObjectID]] = [:]
        
        // 1. Collect nodes relevant to the simulation
        for node in unorderedSimulationNodes {
            guard let name = node.name else {
                throw .attributeExpectationFailure(node.id, "name")
            }
            homonyms[name, default: []].append(node.id)
        }
        
        // 2. Sort nodes based on computation dependency.
        let parameterDependency = Graph(nodes: unorderedSimulationNodes,
                                        edges: view.parameterEdges)
        
        guard let ordered = parameterDependency.topologicalSort() else {
            let cycleEdges = parameterDependency.cycles()
            var nodes: Set<ObjectID> = Set()

            for edge in cycleEdges {
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                appendIssue(.computationCycle, for: edge.id)
            }
            for node in nodes {
                appendIssue(ObjectIssue.computationCycle, for: node)
            }
            throw .hasIssues
        }
        
        // 3. Report the duplicates, if any
        
        var dupes: [String] = []
        
        for (name, ids) in homonyms where ids.count > 1 {
            let issue = ObjectIssue.duplicateName(name)
            dupes.append(name)
            for id in ids {
                appendIssue(issue, for: id)
            }
        }
        
        if hasIssues {
            throw .hasIssues
        }

        self.orderedObjects = ordered.map { frame.object($0) }
    }

    func parseExpressions() throws (CompilerError) {
        // TODO: This does not have to be in the Compiler
        parsedExpressions = [:]
        
        for object in orderedObjects {
            guard let formula = try? object["formula"]?.stringValue() else {
                continue
            }
            let parser = ExpressionParser(string: formula)
            let expr: UnboundExpression
            
            do {
                expr = try parser.parse()
            }
            catch { // is ExpressionSyntaxError
                appendIssue(.expressionSyntaxError(error), for: object.id)
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
            throw .attributeExpectationFailure(object.id, "name")
        }

        // Determine simulation type
        //
        let simType: SimulationObject.SimulationObjectType
        if object.type === ObjectType.Stock {
            simType = .stock
        }
        else if object.type === ObjectType.Flow {
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
            throw .attributeExpectationFailure(object.id, "formula")
        }
        
        // List of required parameters: variables in the expression that
        // are not built-in variables.
        //
        let required: [String] = unboundExpression.allVariables.filter {
            !builtinVariableNames.contains($0)
        }
        
        // TODO: Move this outside of this method. This is not required for binding
        // Validate parameters.
        //
        let parameterIssues = validateParameters(object.id, required: required)
        appendIssues(parameterIssues, for: object.id)
        
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
            appendIssue(.expressionError(error), for: object.id)
            throw .hasIssues
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
            throw CompilerError.attributeExpectationFailure(object.id, "graphical_function_points")
        }
        // TODO: Interpolation method
        let function = GraphicalFunction(points: points)
        
        let hood = view.incomingParameters(object.id)
        guard let parameterNode = hood.nodes.first else {
            appendIssue(ObjectIssue.missingRequiredParameter, for: object.id)
            throw .hasIssues
        }
        
        let funcName = "__graphical_\(object.id)"
        let numericFunc = function.createFunction(name: funcName)
        
        return .graphicalFunction(numericFunc, objectVariableIndex[parameterNode.id]!)
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

        let hood = view.incomingParameters(object.id)
        guard let parameterNode = hood.nodes.first else {
            appendIssue(ObjectIssue.missingRequiredParameter, for: object.id)
            throw .hasIssues
        }
        
        let parameterIndex = objectVariableIndex[parameterNode.id]!
        let variable = stateVariables[parameterIndex]
        
        guard let duration = try? object["delay_duration"]?.intValue() else {
            throw .attributeExpectationFailure(object.id, "delay_duration")
        }

        let initialValue = object["initial_value"]
        
        guard case let .atom(atomType) = variable.valueType else {
            appendIssue(.unsupportedDelayValueType(variable.valueType), for: object.id)
            throw .hasIssues
        }
        
        // TODO: Check whether the initial value and variable.valueType are the same
        let compiled = CompiledDelay(
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

        let hood = view.incomingParameters(object.id)
        guard let parameterNode = hood.nodes.first else {
            appendIssue(ObjectIssue.missingRequiredParameter, for: object.id)
            throw .hasIssues
        }
        
        let parameterIndex = objectVariableIndex[parameterNode.id]!
        let variable = stateVariables[parameterIndex]
        
        guard let windowTime = try? object["window_time"]?.doubleValue() else {
            throw .attributeExpectationFailure(object.id, "window_time")
        }

        guard case .atom(_) = variable.valueType else {
            appendIssue(.unsupportedDelayValueType(variable.valueType), for: object.id)
            throw .hasIssues
        }
        
        let compiled = CompiledSmooth(
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
    func compileStocksAndFlows() throws (CompilerError) {
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
                appendIssue(.flowCycle, for: edge.id)
            }
            for node in nodes {
                appendIssue(ObjectIssue.flowCycle, for: node)
            }
            throw .hasIssues
        }

        let sortedStocks = sorted.map { frame.object($0) }

        for edge in view.drainsEdges {
            let (stock, flow) = (edge.origin, edge.target)
            outflows[stock,default:[]].append(flow)
        }
        
        for edge in view.fillsEdges {
            let (flow, stock) = (edge.origin, edge.target)
            inflows[stock, default: []].append(flow)
        }
        
        // Sort the outflows by priority
        for flow in flows {
            guard let priority = try? flow["priority"]?.intValue() else {
                throw .attributeExpectationFailure(flow.id, "priority")
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
        
        var result: [CompiledStock] = []
        
        for object in sortedStocks {
            let inflowIndices = inflows[object.id]?.map { objectVariableIndex[$0]! } ?? []
            let outflowIndices = outflows[object.id]?.map { objectVariableIndex[$0]! } ?? []
            
            // We can `try!` and force unwrap, because here we already assume
            // the model was validated
            let allowsNegative = try! object["allows_negative"]!.boolValue()
            let delayedInflow = try! object["delayed_inflow"]!.boolValue()
            
            let compiled = CompiledStock(
                id: object.id,
                variableIndex: objectVariableIndex[object.id]!,
                allowsNegative: allowsNegative,
                delayedInflow: delayedInflow,
                inflows: inflowIndices,
                outflows: outflowIndices
            )
            result.append(compiled)
        }

        self.compiledStocks = result
    }

    /// Validates parameter of a node.
    ///
    /// The method checks whether the following two requirements are met:
    ///
    /// - node using a parameter name in an expression (in the `required` list)
    ///   must have a ``/PoieticCore/ObjectType/Parameter`` edge from the parameter node
    ///   with given name.
    /// - node must _not_ have a ``/PoieticCore/ObjectType/Parameter``connection from
    ///   a node if the expression is not referring to that node.
    ///
    /// If any of the two requirements are not met, then a corresponding
    /// type of ``ObjectIssue`` is added to the list of issues.
    ///
    /// - Parameters:
    ///     - nodeID: ID of a node to be validated for inputs
    ///     - required: List of names (of nodes) that are required for the node
    ///       with an id `nodeID`.
    ///
    /// - Returns: List of issues that the node with ID `nodeID` caused. The
    ///   issues can be either ``ObjectIssue/unknownParameter(_:)`` or
    ///   ``ObjectIssue/unusedInput(_:)``.
    ///
    public func validateParameters(_ nodeID: ObjectID, required: [String]) -> [ObjectIssue] {
        let parameters = view.resolveParameters(nodeID, required: required)
        var issues: [ObjectIssue] = []
        
        for name in parameters.missing {
            issues.append(.unusedInput(name))
        }
        for edge in parameters.unused {
            guard let name = frame.object(edge.origin).name else {
                fatalError("Expected named object")
            }
            issues.append(.unknownParameter(name))
        }
        
        return issues
    }

    func compileCharts() throws (CompilerError) -> [Chart] {
        let nodes = frame.filter { $0.type === ObjectType.Chart }
        
        var charts: [PoieticFlows.Chart] = []
        for node in nodes {
            let hood = frame.hood(node.id, direction: .outgoing) {
                $0.type === ObjectType.ChartSeries
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
            guard let edge = EdgeObject(object) else {
                throw .structureTypeMismatch(object.id)
            }
            
            guard let index = objectVariableIndex[edge.target] else {
                throw .objectNotFound(edge.target)
            }
            let binding = CompiledControlBinding(control: edge.origin,
                                                 variableIndex: index)
            bindings.append(binding)
        }
        return bindings
    }

    public func compileDefaults() throws (CompilerError) -> SimulationDefaults? {
        guard let simInfo = frame.first(trait: Trait.Simulation) else {
            return nil
        }
        let initialTime = try! simInfo["initial_time"]?.doubleValue()
        let timeDelta = try! simInfo["time_delta"]?.doubleValue()
        let steps = try! simInfo["steps"]?.intValue()
        return SimulationDefaults(initialTime: initialTime ?? 0.0,
                                  timeDelta: timeDelta ?? 1.0,
                                  simulationSteps: steps ?? 10)
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
