//
//  Compiler.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

import PoieticCore


/// Error thrown by the compiler during compilation.
public enum CompilerError: Error {
//    / Object type is not recognised by the compiler. Validation must have failed.
//    case unrecognizedObjectType(ObjectID, ObjectType)
    
    /// Object has issues, they were added to the list of issues
    case hasIssues

    // Invalid Frame Error - validation on the caller side failed
    case structureTypeMismatch(ObjectID)
    case objectNotFound(ObjectID)
    case invalidAttribute(ObjectID, String)
    case attributeTypeMismatch(ObjectID, String, ValueType)
    case expectedAttribute(ObjectID, String)
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
    public let frame: StableFrame
    
    /// Flows domain view of the frame.
    public let view: StockFlowView

    // MARK: - Compiler State
    // -----------------------------------------------------------------
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
    public var issues: [ObjectID: [NodeIssue]]

    /// List of built-in functions.
    ///
    /// Used in binding of arithmetic expressions.
    private let functions: [String: Function]

    private var builtins: [CompiledBuiltin] = []
    /// List of built-in variable names, fetched from the metamodel.
    ///
    /// Used in binding of arithmetic expressions.
    private var builtinVariableNames: [String]

    /// Mapping between a variable name and a bound variable reference.
    ///
    /// Used in binding of arithmetic expressions.
    private var namedReferences: [String:SimulationState.Index]
    
    private var parsedExpressions: [ObjectID:UnboundExpression]

    /// Mapping between object ID and index of its corresponding simulation
    /// variable.
    ///
    /// Used in compilation of simulation nodes.
    ///
    private var objectToVariable: [ObjectID: Int]

    // Extracted
    // INPUT
    private var orderedObjects: [ObjectSnapshot]

    // OUTPUT
    private var simulationObjects: [SimulationObject] = []
    private var stocks: [ObjectSnapshot]
    private var flows: [ObjectSnapshot]
    
    var compiledStocks: [CompiledStock] = []

    /// Appends an error to the list of of node issues
    ///
    public func appendIssue(_ error: NodeIssue, for id: ObjectID) {
        issues[id, default:[]].append(error)
    }
    
    /// Append a list of issues to an object.
    ///
    public func appendIssues(_ errors: [NodeIssue], for id: ObjectID) {
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
    public init(frame: StableFrame) {
        self.frame = frame
        self.view = StockFlowView(frame)
        
        stateVariables = []
        builtinVariableNames = []

        var functions:[String:Function] = [:]
        for function in AllBuiltinFunctions {
            functions[function.name] = function
        }
        self.functions = functions

        issues = [:]
        orderedObjects = []
        parsedExpressions = [:]

        namedReferences = [:]

        objectToVariable = [:]
        stocks = []
        flows = []
    }

    // - MARK: State Queries
    
    /// Get an index of a simulation variable that represents a node with given
    /// ID.
    ///
    /// - Precondition: Object with given ID must have a corresponding
    ///   simulation variable.
    ///
    public func variableIndex(_ id: ObjectID) -> SimulationState.Index {
        guard let index = objectToVariable[id] else {
            fatalError("Object \(id) not found in the simulation variable list")
        }
        return index
    }

    /// Get a list of issues for given object.
    ///
    public func issues(for id: ObjectID) -> [NodeIssue] {
        return issues[id] ?? []
    }

    // - MARK: Compilation
    /// Compiles the design and returns compiled model that can be simulated.
    ///
    /// The compilation process is as follows:
    ///
    /// 1. Gather all node names and check for potential duplicates
    /// 2. Compile all formulas (expressions) and bind them with concrete
    ///    objects.
    /// 3. Sort the nodes in the order of computation.
    /// 4. Pre-filter nodes for easier usage by the solver: stocks, flows
    ///    and auxiliaries. All filtered collections stay ordered.
    /// 5. Create implicit flows between stocks and sort stocks in order
    ///    of their dependency.
    /// 6. Finalise the compiled model.
    ///
    /// - Throws: A ``NodeIssuesError`` when there are issues with the model
    ///   that are caused by the user. Throws ``/PoieticCore/ConstraintViolation`` if
    ///   the frame constraints were violated. The later error is an
    ///   application error and means that either the provided frame is
    ///   malformed or one of the subsystems mis-behaved.
    /// - Returns: A ``CompiledModel`` that can be used directly by the
    ///   simulator.
    ///
    public func compile() throws (CompilerError) -> CompiledModel {
        try initialize()
        try prepareBuiltins()
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

        guard let timeIndex = namedReferences["time"] else {
            fatalError("No time variable within the builtins.")
        }

        return CompiledModel(
            simulationObjects: self.simulationObjects,
            stateVariables: self.stateVariables,
            builtins: self.builtins,
            timeVariableIndex: timeIndex,
            stocks: self.compiledStocks,
            charts: view.charts,
            valueBindings: bindings,
            simulationDefaults: defaults
        )
    }
    
    /// - Precondition: Simulation nodes must have a name
    ///
    func initialize() throws (CompilerError) {
        issues = [:]
        
        var unordered: [ObjectID] = []
        var homonyms: [String: [ObjectID]] = [:]
        
        // 1. Collect nodes relevant to the simulation
        for node in view.simulationNodes {
            unordered.append(node.id)
            homonyms[node.name!, default: []].append(node.id)
        }
        
        // 2. Sort nodes based on computation dependency.
        
        let ordered: [Node]
        
        do {
            ordered = try view.sortedNodesByParameter(unordered)
        }
        catch {
            var nodes: Set<ObjectID> = Set()
            for edgeID in error.edges {
                let edge = frame.edge(edgeID)
                nodes.insert(edge.origin)
                nodes.insert(edge.target)
                // TODO: Add EdgeIssue.computationCycle
            }
            for node in nodes {
                appendIssue(NodeIssue.computationCycle, for: node)
            }
            throw .hasIssues
        }
        
        // 3. Report the duplicates, if any
        
        var dupes: [String] = []
        
        for (name, ids) in homonyms where ids.count > 1 {
            let issue = NodeIssue.duplicateName(name)
            dupes.append(name)
            for id in ids {
                appendIssue(issue, for: id)
            }
        }
        
        if hasIssues {
            throw .hasIssues
        }
        
        orderedObjects = ordered.map { $0.snapshot }
    }
    
    func parseExpressions() throws (CompilerError) {
        // TODO: This does not require to be in the Compiler
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
            catch let error as ExpressionSyntaxError {
                appendIssue(.expressionSyntaxError(error), for: object.id)
                continue
            }
            catch {
                fatalError("Unknown error during parsing: \(error)")
            }
            
            parsedExpressions[object.id] = expr
        }
    }

    func prepareBuiltins() throws (CompilerError) {
        var builtins: [CompiledBuiltin] = []

        for variable in Simulator.BuiltinVariables {
            let builtin: BuiltinVariable
            if variable === Variable.TimeVariable {
                builtin = .time
            }
            else if variable === Variable.TimeDeltaVariable {
                builtin = .timeDelta
            }
            else if variable === Variable.SimulationStepVariable {
                builtin = .step
            }
            else {
                fatalError("Unknown builtin variable: \(variable)")
            }
            
            let index = createStateVariable(content: .builtin(builtin),
                                            valueType: variable.valueType,
                                            name: variable.name)
            
            self.namedReferences[variable.name] = index
            builtins.append(CompiledBuiltin(builtin: builtin,
                                            variableIndex: index))
        }
        self.builtins = builtins
        self.builtinVariableNames = builtins.map { $0.builtin.name }
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
    public func compile(_ object: ObjectSnapshot) throws (CompilerError) {
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
//            throw .unrecognizedObjectType(object.id, object.type)
            fatalError("Unknown simulation object type \(object.type.name), object: \(object.id)")
        }

        guard let name = object.name else {
            throw .expectedAttribute(object.id, "name")
        }

        // Determine simulation type
        //
        let simType: SimulationObject.SimulationObjectType
        if object.type === ObjectType.Stock {
            simType = .stock
            stocks.append(object)
        }
        else if object.type === ObjectType.Flow {
            simType = .flow
            flows.append(object)
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
        self.objectToVariable[object.id] = index
        self.namedReferences[name] = index

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
    public func compileFormulaObject(_ object: ObjectSnapshot) throws (CompilerError) -> ComputationalRepresentation {
        guard let unboundExpression = parsedExpressions[object.id] else {
            throw .expectedAttribute(object.id, "formula")
        }
        
        // List of required parameters: variables in the expression that
        // are not built-in variables.
        //
        let required: [String] = unboundExpression.allVariables.filter {
            !builtinVariableNames.contains($0)
        }
        
        // TODO: [IMPORTANT] Move this outside of this method. This is not required for binding
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
                                                 names: namedReferences,
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
    public func compileGraphicalFunctionNode(_ object: ObjectSnapshot) throws (CompilerError) -> ComputationalRepresentation{
        guard let points = try? object["graphical_function_points"]?.pointArray() else {
            throw CompilerError.attributeTypeMismatch(object.id, "graphical_function_points", .points)
        }
        // TODO: Interpolation method
        let function = GraphicalFunction(points: points)
        
        let hood = view.incomingParameters(object.id)
        guard let parameterNode = hood.nodes.first else {
            appendIssue(NodeIssue.missingRequiredParameter, for: object.id)
            throw .hasIssues
        }
        
        let funcName = "__graphical_\(object.id)"
        let numericFunc = function.createFunction(name: funcName)
        
        return .graphicalFunction(numericFunc, variableIndex(parameterNode.id))
    }
    
    /// Compile a delay node.
    ///
    public func compileDelayNode(_ object: ObjectSnapshot) throws (CompilerError) -> ComputationalRepresentation{
        // TODO: What to do if the input is not numeric or not an atom?
        let queueIndex = createStateVariable(content: .internalState(object.id),
                                             valueType: .doubles,
                                             name: "delay_queue_\(object.id)")
        
        let initialValueIndex = createStateVariable(content: .internalState(object.id),
                                             valueType: .doubles,
                                             name: "delay_init_\(object.id)")

        let hood = view.incomingParameters(object.id)
        guard let parameterNode = hood.nodes.first else {
            appendIssue(NodeIssue.missingRequiredParameter, for: object.id)
            throw .hasIssues
        }
        
        let parameterIndex = variableIndex(parameterNode.id)
        let variable = stateVariables[parameterIndex]
        
        guard let durationAttr = object["delay_duration"] else {
            throw .expectedAttribute(object.id, "delay_duration")
        }
        guard let duration = try? durationAttr.intValue() else {
            throw .attributeTypeMismatch(object.id, "delay_duration", .int)
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
    public func compileSmoothNode(_ object: ObjectSnapshot) throws (CompilerError) -> ComputationalRepresentation{
        let smoothValueIndex = createStateVariable(content: .internalState(object.id),
                                             valueType: .doubles,
                                             name: "smooth_value_\(object.id)")

        let hood = view.incomingParameters(object.id)
        guard let parameterNode = hood.nodes.first else {
            appendIssue(NodeIssue.missingRequiredParameter, for: object.id)
            throw .hasIssues
        }
        
        let parameterIndex = variableIndex(parameterNode.id)
        let variable = stateVariables[parameterIndex]
        
        guard let windowTimeAttr = object["window_time"] else {
            throw .expectedAttribute(object.id, "window_time")
        }
        guard let windowTime = try? windowTimeAttr.doubleValue() else {
            throw .attributeTypeMismatch(object.id, "window_time", .int)
        }

        guard case let .atom(atomType) = variable.valueType else {
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
    public func compileStocksAndFlows() throws (CompilerError) {
        let unsortedStocks = stocks.map { $0.id }
        var flowPriorities: [ObjectID:Int] = [:]
        var outflows: [ObjectID: [ObjectID]] = [:]
        var inflows: [ObjectID: [ObjectID]] = [:]
        
        // This step is needed for proper computation of non-negative stocks
        let sortedStocks: [ObjectSnapshot]
        // Stock adjacencies without delayed input - break the cycle at stocks
        // with delayed_input=true.
        let adjacencies = self.stockAdjacencies().filter { !$0.targetHasDelayedInflow }
        
        do {
            let sorted = try topologicalSort(unsortedStocks, edges: adjacencies)
            sortedStocks = sorted.map { frame.object($0) }
        }
        catch {  // GraphCycleError
            var nodes: Set<ObjectID> = Set()
            for adjacency in adjacencies {
                // NOTE: The adjacency.id is ID of a flow connecting two stocks,
                //       not an ID of a graph edge (as structural type)
                guard error.edges.contains(adjacency.id) else {
                    continue
                }
                nodes.insert(adjacency.origin)
                nodes.insert(adjacency.target)
            }
            for node in nodes {
                appendIssue(NodeIssue.flowCycle, for: node)
            }
            throw .hasIssues
        }
        
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
                // FIXME: Thow compilation error
                fatalError("Invalid frame: Unable to get priority of Flow node \(flow.id)")
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
            let inflowIndices = inflows[object.id]?.map { variableIndex($0) } ?? []
            let outflowIndices = outflows[object.id]?.map { variableIndex($0) } ?? []
            
            // We can `try!` and force unwrap, because here we already assume
            // the model was validated
            let allowsNegative = try! object["allows_negative"]!.boolValue()
            let delayedInflow = try! object["delayed_inflow"]!.boolValue()
            
            let compiled = CompiledStock(
                id: object.id,
                variableIndex: variableIndex(object.id),
                allowsNegative: allowsNegative,
                delayedInflow: delayedInflow,
                inflows: inflowIndices,
                outflows: outflowIndices
            )
            result.append(compiled)
        }

        self.compiledStocks = result
    }

    /// Get a list of stock-to-stock adjacency.
    ///
    /// Two stocks are adjacent if there is a flow that connects the two stocks.
    /// One stock is being drained – origin of the adjacency,
    /// another stock is being filled – target of the adjacency.
    ///
    /// The following diagram depicts two adjacent stocks, where the stock `a`
    /// would be the origin and stock `b` would be the target:
    ///
    /// ```
    ///              Drains           Fills
    ///    Stock a ==========> Flow =========> Stock b
    ///       ^                                  ^
    ///       +----------------------------------+
    ///                  adjacent stocks
    ///
    /// ```
    ///
    public func stockAdjacencies() -> [StockAdjacency] {
        var adjacencies: [StockAdjacency] = []

        for flow in view.flowNodes {
            guard let fills = view.flowFills(flow.id) else {
                continue
            }
            guard let drains = view.flowDrains(flow.id) else {
                continue
            }

            // TODO: Too much going on in here. Simplify. Move some of it to where we collect unsortedStocks in the Compiler.
            let delayedInflow = try! frame[drains]["delayed_inflow"]!.boolValue()
            
            let adjacency = StockAdjacency(id: flow.id,
                                           origin: drains,
                                           target: fills,
                                           targetHasDelayedInflow: delayedInflow)

            adjacencies.append(adjacency)
        }
        return adjacencies
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
    /// type of ``NodeIssue`` is added to the list of issues.
    ///
    /// - Parameters:
    ///     - nodeID: ID of a node to be validated for inputs
    ///     - required: List of names (of nodes) that are required for the node
    ///       with an id `nodeID`.
    ///
    /// - Returns: List of issues that the node with ID `nodeID` caused. The
    ///   issues can be either ``NodeIssue/unknownParameter(_:)`` or
    ///   ``NodeIssue/unusedInput(_:)``.
    ///
    public func validateParameters(_ nodeID: ObjectID, required: [String]) -> [NodeIssue] {
        let parameters = view.parameters(nodeID, required: required)
        var issues: [NodeIssue] = []
        
        for (name, status) in parameters {
            switch status {
            case .used: continue
            case .unused:
                issues.append(.unusedInput(name))
            case .missing:
                issues.append(.unknownParameter(name))
            }
        }
        
        return issues
    }

    public func compileControlBindings() throws (CompilerError) -> [CompiledControlBinding] {
        // 8. Value Bindings
        // =================================================================
        
        var bindings: [CompiledControlBinding] = []
        for object in frame.filter(type: ObjectType.ValueBinding) {
            guard let edge = Edge(object) else {
                throw .structureTypeMismatch(object.id)
            }
            
            guard let index = objectToVariable[edge.target] else {
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
    ///       See ``StateVariableContent`` for more information.
    ///     - valueType: Type of the state variable value.
    ///     - name: Name of the state variable.
    ///
    public func createStateVariable(content: StateVariableContent,
                                    valueType: ValueType,
                                    name: String) -> SimulationState.Index {
        // TODO: Rename to "allocate..."
        let variableIndex = stateVariables.count
        let variable = StateVariable(index: variableIndex,
                                     content: content,
                                     valueType: valueType,
                                     name: name)
        stateVariables.append(variable)
        
        if case let .object(id) = content {
            objectToVariable[id] = variableIndex
        }
        
        return variableIndex
    }
}
