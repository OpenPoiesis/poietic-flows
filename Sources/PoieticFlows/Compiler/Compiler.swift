//
//  Compiler.swift
//
//
//  Created by Stefan Urbanek on 21/06/2022.
//

import PoieticCore

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
    // TODO: Make the compiler into a RuntimeSystem
    /// The frame containing the design to be compiled.
    ///
    public let frame: StableFrame
    
    /// Flows domain view of the frame.
    public let view: StockFlowView
    
    // Compiler State
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
    public private(set) var stateVariables: [StateVariable] = []
    
    /// Index of the current state
    public private(set) var currentVariableIndex = 0
    
    
    /// List of built-in variables used in the simulation.
    ///
    private let builtinVariables: [Variable]
    
    /// List of built-in variable names, fetched from the metamodel.
    ///
    /// Used in binding of arithmetic expressions.
    private let builtinVariableNames: [String]
    
    /// List of built-in functions.
    ///
    /// Used in binding of arithmetic expressions.
    private let functions: [String: Function]
    
    /// Mapping between a variable name and a bound variable reference.
    ///
    /// Used in binding of arithmetic expressions.
    private var namedReferences: [String:SimulationState.Index]
    
    /// Mapping between object ID and index of its corresponding simulation
    /// variable.
    ///
    /// Used in compilation of simulation nodes.
    ///
    private var objectToVariable: [ObjectID: Int]
    
    // TODO: Change to system dependency chain
    /// List of transformation systems run before the compilation.
    ///
    /// Requirements:
    /// - There must be no dependency between the systems.
    /// - If any of the systems reports a node issue, the compilation must not
    ///   proceed.
    ///
    /// - Note: This will be public once happy.
    ///
    private var _preCompilationSystems: [any RuntimeSystem] = [
        FormulaCompilerSystem(),
    ]
    //    private var _postCompilationSystems: [any RuntimeSystem] = [
    //    ]
    
    /// Creates a compiler that will compile within the context of the given
    /// model.
    ///
    public init(frame: StableFrame) {
        // NOTE: [IMPORTANT] The functionality/architectural decision about
        //       mutability is not yet well formed.
        //
        // TODO: [IMPORTANT] Do not pass frame on init, use it on "compile"
        self.frame = frame
        self.view = StockFlowView(frame)
        
        builtinVariables = Solver.Variables
        builtinVariableNames = builtinVariables.map { $0.name }
        
        let items = AllBuiltinFunctions.map { ($0.name, $0) }
        functions = Dictionary(uniqueKeysWithValues: items)
        
        // Intermediated variables and mappigns used for compilation
        objectToVariable = [:]
        
        // Variables for arithmetic expression binding
        namedReferences = [:]
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
        let variableIndex = currentVariableIndex
        let variable = StateVariable(index: variableIndex,
                                     content: content,
                                     valueType: valueType,
                                     name: name)
        stateVariables.append(variable)
        currentVariableIndex += 1
        
        if case let .object(id) = content {
            objectToVariable[id] = variableIndex
        }
        
        return variableIndex
    }
    
    // TODO: Verify which errors are thrown in here
    /// Compiles the model and returns the compiled version of the model.
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
    public func compile() throws (NodeIssuesError) -> CompiledModel {
        // NOTE: Please use explicit self for instance variables in this function
        //       so we can visually see the shared compilation context.
        //
        // Context:
        //  - unsorted simulation nodes
        //      - (id, name, computationalRepresentation)
        var simulationObjects: [SimulationObject] = []
        
        // 1. Update pre-compilation systems
        // =================================================================
        
        // TODO: We are passing view from metamodel just to create view in the context
        let context = RuntimeContext(frame: frame)
        
        for index in _preCompilationSystems.indices {
            _preCompilationSystems[index].update(context)
        }
        
        guard !context.hasIssues else {
            throw NodeIssuesError(errors: context.issues)
        }
        
        // 2. Collect nodes that are to be part of the simulation
        // =================================================================
        
        var unsortedSimulationNodes: [ObjectID] = []
        var homonyms: [String: [ObjectID]] = [:]
        
        for node in view.simulationNodes {
            unsortedSimulationNodes.append(node.id)
            homonyms[node.name!, default: []].append(node.id)
        }
        
        // 2.1 Report the duplicates, if any
        // -----------------------------------------------------------------
        
        var dupes: [String] = []
        
        for (name, ids) in homonyms where ids.count > 1 {
            let issue = NodeIssue.duplicateName(name)
            dupes.append(name)
            for id in ids {
                context.appendIssue(issue, for: id)
            }
        }
        
        guard !context.hasIssues else {
            throw NodeIssuesError(errors: context.issues)
        }
        
        // 3. Sort nodes in order of computation
        // =================================================================
        // All the nodes present in this list will form a simulation state.
        // Indices in this vector will be the indices used through out the
        // simulation.
        
        let orderedSimulationNodes: [Node]
        // TODO: orderedSimulationNodes should be (id, name, snapshot)
        
        do {
            orderedSimulationNodes = try view.sortedNodesByParameter(unsortedSimulationNodes)
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
                context.appendIssue(NodeIssue.computationCycle, for: node)
            }
            throw NodeIssuesError(errors: context.issues)
        }
        
        // 4. Prepare named references to variables
        // =================================================================
        // This step is necessary for arithmetic expression compilation.
        
        // Collect built-in variables.
        //
        var builtins: [CompiledBuiltin] = []
        
        for variable in builtinVariables {
            let builtin: BuiltinVariable
            if variable === Variable.TimeVariable {
                builtin = .time
            }
            else if variable === Variable.TimeDeltaVariable {
                builtin = .timeDelta
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
        
        guard let timeIndex = namedReferences["time"] else {
            fatalError("No time variable within the builtins.")
        }
        
        // 5. Compile computational representations
        // =================================================================
        
        var issues = NodeIssuesError()
        // FIXME: Use context, test whether the errors were appended to the node
        
        for node in orderedSimulationNodes {
            guard let name = node.name else {
                fatalError("Node \(node.id) has no name. Validation before compilation failed.")
            }
            
            let computation: ComputationalRepresentation
            do {
                computation = try self.compile(node, in: context)
            }
            catch { // NodeIssuesError
                // TODO: Remove necessity for this catch
                issues.merge(error)
                continue
            }
            
            let index = createStateVariable(content: .object(node.id),
                                            valueType: computation.valueType,
                                            name: name)
            // Determine simulation type
            //
            let objectType: SimulationObject.SimulationObjectType
            if node.snapshot.type === ObjectType.Stock {
                objectType = .stock
            }
            else if node.snapshot.type === ObjectType.Flow {
                objectType = .flow
            }
            else if node.type === ObjectType.Auxiliary
                        || node.type === ObjectType.GraphicalFunction
                        || node.type === ObjectType.Delay {
                objectType = .auxiliary
            }
            else {
                fatalError("Unknown simulation node type: \(node.type.name)")
            }
            
            let object = SimulationObject(id: node.id,
                                          type: objectType,
                                          variableIndex: index,
                                          valueType: computation.valueType,
                                          computation: computation,
                                          name: name)
            simulationObjects.append(object)
            
            
            self.namedReferences[name] = index
            self.objectToVariable[node.id] = index
        }
        
        guard issues.isEmpty else {
            throw issues
        }
        
        // 6. Filter by node type
        // =================================================================
        
        var unsortedStocks: [Node] = []
        var flowsByID: [ObjectID:CompiledFlow] = [:]
        
        for (objectIndex, item) in zip(orderedSimulationNodes, simulationObjects).enumerated() {
            let (node, object) = item
            
            switch object.type {
            case .stock:
                unsortedStocks.append(node)
                
            case .flow:
                guard let priority = try? node.snapshot["priority"]?.intValue() else {
                    fatalError("Unable to get priority of Stock node \(node.id). Hint: Frame passed constraint validation while it should have not.")
                }
                
                let flow = CompiledFlow(id: object.id, priority: priority)
                flowsByID[object.id] = flow
                
            case .auxiliary:
                // Nothing special to be done
                break
            }
        }
        
        // 7. Sort stocks in order of flow dependency
        // =================================================================
        
        // This step is needed for proper computation of non-negative stocks
        
        let sortedStocks: [Node]
        // Stock adjacencies without delayed input - break the cycle at stocks
        // with delayed_input=true.
        let adjacencies = self.stockAdjacencies().filter {
            !$0.targetHasDelayedInflow
        }
        do {
            // TODO: There is too much node/edge wrap/unwrap overhead in here
            let unsorted = unsortedStocks.map { $0.id }
            let sorted = try topologicalSort(unsorted, edges: adjacencies)
            sortedStocks = sorted.map { frame.node($0) }
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
                context.appendIssue(NodeIssue.flowCycle, for: node)
            }
            throw NodeIssuesError(errors: context.issues)
        }
        
        let compiledStocks = compile(stocks: sortedStocks, flows: flowsByID)
        
        // 8. Value Bindings
        // =================================================================
        
        var bindings: [CompiledControlBinding] = []
        for object in frame.filter(type: ObjectType.ValueBinding) {
            guard let edge = Edge(object) else {
                // This should not happen
                fatalError("A value binding \(object.id) is not an edge")
            }
            
            // TODO: Better error reporting
            guard let index = objectToVariable[edge.target] else {
                fatalError("Unknown index of object: \(edge.target), compilation failed")
            }
            let binding = CompiledControlBinding(control: edge.origin,
                                                 variableIndex: index)
            bindings.append(binding)
        }
        
        // 9. Charts
        // =================================================================
        //
        // TODO: [RELEASE] Move StockFlowView.charts here
        let charts = view.charts
        
        // 10. Defaults
        // =================================================================
        //
        let simulationDefaults: SimulationDefaults?
        if let simInfo = frame.first(trait: Trait.Simulation) {
            // NOTE: We do not need to check for types as the type
            //       is validated on accept(). Frame is valid here.
            let initialTime = try! simInfo["initial_time"]?.doubleValue()
            let timeDelta = try! simInfo["time_delta"]?.doubleValue()
            let steps = try! simInfo["steps"]?.intValue()
            simulationDefaults = SimulationDefaults(
                initialTime: initialTime ?? 0.0,
                timeDelta: timeDelta ?? 1.0,
                simulationSteps: steps ?? 10
            )
        }
        else {
            simulationDefaults = nil
        }
        
        // 999. Misc
                
        // Finalise
        // =================================================================
        //
        let result = CompiledModel(
            simulationObjects: simulationObjects,
            stateVariables: self.stateVariables,
            builtins: builtins,
            timeVariableIndex: timeIndex,
            stocks: compiledStocks,
            charts: charts,
            valueBindings: bindings,
            simulationDefaults: simulationDefaults
        )
        
        return result
    }
    
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
    public func compile(_ node: Node, in context: RuntimeContext) throws (NodeIssuesError) -> ComputationalRepresentation {
        let rep: ComputationalRepresentation
        if node.snapshot.type.hasTrait(Trait.Formula) {
            rep = try compileFormulaNode(node, in: context)
        }
        else if node.snapshot.type.hasTrait(Trait.GraphicalFunction) {
            rep = try compileGraphicalFunctionNode(node)
        }
        else if node.snapshot.type.hasTrait(Trait.Delay) {
            rep = try compileDelayNode(node)
        }
        else {
            // Hint: If this error happens, then either check the following:
            // - the condition in the stock-flows view method returning
            //   simulation nodes
            // - whether the object design constraints work properly
            // - whether the object design metamodel is stock-flows metamodel
            //   and that it has necessary components
            //
            fatalError("Node \(node.snapshot) is not known as a simulation node, can not be compiled.")
        }
        return rep
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
    public func compileFormulaNode(_ node: Node, in context: RuntimeContext) throws (NodeIssuesError) -> ComputationalRepresentation {
        guard let component: ParsedFormulaComponent = context.component(for: node.id) else {
            fatalError("Parsed formula component expected for node \(node.id)")
        }
        
        let unboundExpression: UnboundExpression = component.parsedFormula
        
        // List of required parameters: variables in the expression that
        // are not built-in variables.
        //
        let required: [String] = unboundExpression.allVariables.filter {
            !builtinVariableNames.contains($0)
        }
        
        // TODO: [IMPORTANT] Move this outside of this method. This is not required for binding
        // Validate parameters.
        //
        let inputIssues = validateParameters(node.id, required: required)
        guard inputIssues.isEmpty else {
            throw NodeIssuesError(errors: [node.id: inputIssues])
        }
        
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
            throw NodeIssuesError(errors: [node.id: [NodeIssue.expressionError(error)]])
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
    public func compileGraphicalFunctionNode(_ node: Node) throws (NodeIssuesError) -> ComputationalRepresentation{
        guard let points = try? node.snapshot["graphical_function_points"]?.pointArray() else {
            // TODO: [RELEASE] Better error handling/reporting for these cases
            fatalError("Got graphical function without points attribute")
        }
        // TODO: Interpolation method
        let function = GraphicalFunction(points: points)
        
        let hood = view.incomingParameters(node.id)
        guard let parameterNode = hood.nodes.first else {
            throw NodeIssuesError(errors: [node.id: [NodeIssue.missingRequiredParameter]])
        }
        
        let funcName = "__graphical_\(node.id)"
        let numericFunc = function.createFunction(name: funcName)
        
        return .graphicalFunction(numericFunc, variableIndex(parameterNode.id))
        
    }
    public func compileDelayNode(_ node: Node) throws (NodeIssuesError) -> ComputationalRepresentation{
        // TODO: What to do if the input is not numeric or not an atom?
        let queueIndex = createStateVariable(content: .internalState(node.id),
                                             valueType: .doubles,
                                             name: "delay_queue_\(node.id)")
        
        let initialValueIndex = createStateVariable(content: .internalState(node.id),
                                             valueType: .doubles,
                                             name: "delay_init_\(node.id)")

        let hood = view.incomingParameters(node.id)
        guard let parameterNode = hood.nodes.first else {
            throw NodeIssuesError(errors: [node.id: [NodeIssue.missingRequiredParameter]])
        }
        
        let parameterIndex = variableIndex(parameterNode.id)
        let variable = stateVariables[parameterIndex]
        
        let duration = try! node.snapshot["delay_duration"]!.intValue()
        let initialValue = node.snapshot["initial_value"]
        
        // TODO: Check whether the initial value and variable.valueType are the same
        let compiled = CompiledDelay(
            steps: duration,
            initialValue: initialValue,
            valueType: variable.valueType,
            initialValueIndex: initialValueIndex,
            queueIndex: queueIndex,
            inputValueIndex: parameterIndex
        )
        
        return .delay(compiled)
    }
    /// Compile all stock nodes.
    ///
    /// The function extracts component from the stock that is necessary
    /// for simulation. Then the function collects all inflows and outflows
    /// of the stock.
    ///
    /// - Returns: Extracted and derived stock node information.
    ///
    func compile(stocks: [Node], flows: [ObjectID:CompiledFlow]) -> [CompiledStock] {
        // TODO: Change `flows` argument to flowsPriority: [ObjectID:Int], remove historical remnant CompiledFlow (formerly richer struct)
        var outflows: [ObjectID: [ObjectID]] = [:]
        var inflows: [ObjectID: [ObjectID]] = [:]
        
        for edge in view.drainsEdges {
            // Drains edge: stock ---> flow
            let stock = edge.origin
            let flow = edge.target
            outflows[stock,default:[]].append(flow)
        }
        
        for edge in view.fillsEdges {
            // Fills edge: flow ---> stock
            let stock = edge.target
            let flow = edge.origin
            inflows[stock, default: []].append(flow)
        }
        
        // Sort the outflows by priority
        for stock in stocks {
            if let unsorted = outflows[stock.id] {
                let sorted = unsorted.map {
                    (id: $0, priority: flows[$0]!.priority)
                }
                    .sorted { (lhs, rhs) in
                        return lhs.priority < rhs.priority
                    }
                    .map { $0.id }
                outflows[stock.id] = sorted
            }
            else {
                outflows[stock.id] = []
            }
        }
        
        var result: [CompiledStock] = []
        
        for node in stocks {
            let inflowIndices = inflows[node.id]?.map { variableIndex($0) } ?? []
            let outflowIndices = outflows[node.id]?.map { variableIndex($0) } ?? []
            
            // We can `try!` and force unwrap, because here we already assume
            // the model was validated
            let allowsNegative = try! node.snapshot["allows_negative"]!.boolValue()
            let delayedInflow = try! node.snapshot["delayed_inflow"]!.boolValue()
            
            let compiled = CompiledStock(
                id: node.id,
                variableIndex: variableIndex(node.id),
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

    // FIXME: What was the original intent of this?
    public func appendIssue(_ error: Error, to object: ObjectID) {
        fatalError("\(#function) not implemented")
    }
    
}
