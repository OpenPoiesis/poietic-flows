//
//  CompilationSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 01/11/2025.
//
import PoieticCore

// TODO: Do state variables need name? Can it be optional?

/// Context used to construct state variables.
///
class StateVariableTable {
    var objectIndex: [ObjectID:Int] = [:]
    var nameIndex: [String:Int] = [:]
    var variables: [StateVariable] = []
    
    func allocate(builtin: BuiltinVariable) -> Int
    {
        let index = self.allocate(content: .builtin(builtin),
                                  valueType: builtin.valueType,
                                  name: builtin.name)
        
        return index
    }

    @discardableResult
    func allocate(content: StateVariable.Content,
                                  valueType: ValueType,
                                  name: String) -> Int
    {
        let index = variables.count
        let variable = StateVariable(index: index,
                                     content: content,
                                     valueType: valueType,
                                     name: name)
        variables.append(variable)
        
        if case let .object(id) = content {
            objectIndex[id] = index
        }
        
        nameIndex[name] = index
        return index
    }
   
    func valueType(for objectID: ObjectID) -> ValueType? {
        guard let index = objectIndex[objectID] else { return nil }
        return variables[index].valueType
    }
    func valueType(at index: Int) -> ValueType? {
        return variables[index].valueType
    }
    
    /// Get variable index by name.
    func index(_ name: String) -> Int? {
        return nameIndex[name]
    }
    /// Get variable by name.
    subscript(name: String) -> StateVariable? {
        guard let index = nameIndex[name] else { return nil }
        return variables[index]
    }
    func index(_ objectID: ObjectID) -> Int? {
        return objectIndex[objectID]
    }

    subscript(objectID: ObjectID) -> StateVariable? {
        guard let index = objectIndex[objectID] else { return nil }
        return variables[index]
    }

}

struct SimulationPlanningSystem: System {
    /// Error thrown during the planning process
    internal enum CompilationError: Error, Equatable {
        /// Issue with object has been detected, appended to the list of issues. The caller might
        /// continue with the operation to gather more issues. Criticality of this error is
        /// problem specific.
        case objectIssue
        case corruptedState(String)
        /// Missing required component. Probably the dependency was not satisfied.
        case missingComponent(String)
    }
    
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ExpressionParserSystem.self), // Gets us UnboundExpression for each node
        .after(ComputationOrderSystem.self), // Gets us SimulationOrderComponent
        .after(NameResolutionSystem.self), // We need name lookup and object names.
        .after(FlowCollectorSystem.self),
        .after(StockDependencySystem.self),
    ]
    
    let builtinFunctions: [String:Function]
    
    init() {
        var builtinFunctions: [String:Function] = [:]
        for function in Function.AllBuiltinFunctions {
            builtinFunctions[function.name] = function
        }
        self.builtinFunctions = builtinFunctions
    }
    
    func update(_ world: World) throws (InternalSystemError) {
        guard let frame = world.frame,
              let simOrder: SimulationOrderComponent = world.singleton()
        else { return }
        
        var hasError: Bool = false
        let variables = StateVariableTable()
        var simulationObjects: [SimulationObject] = []
        var flows: [SimulationObject] = []
        var stocks: [SimulationObject] = []

        let builtins = prepareBuiltins(variables: variables)

        for object in simOrder.objects {
            guard let nameComp: SimulationObjectNameComponent = world.component(for: object.objectID),
                  let roleComp: SimulationRoleComponent = world.component(for: object.objectID)
            else {
                hasError = true
                continue
            }
            
            let rep: ComputationalRepresentation

            do {
                rep = try compileObject(object, world: world, variables: variables)
            }
            catch .objectIssue {
                hasError = true
                continue
            }
            catch {
                throw InternalSystemError(self,
                                          message: "Object compilation failed: \(error)",
                                          context: .object(object.objectID))
            }

            let index = variables.allocate(content: .object(object.objectID),
                                           valueType: rep.valueType,
                                           name: nameComp.name)
            
            let sim = SimulationObject(objectID: object.objectID,
                                       computation: rep,
                                       variableIndex: index,
                                       role: roleComp.role,
                                       valueType: rep.valueType,
                                       name: nameComp.name)
       
            
            simulationObjects.append(sim)
            
            switch roleComp.role {
            case .flow: flows.append(sim)
            case .stock: stocks.append(sim)
            default: break
            }
        }

        // If we have errors, finish early without creating the final plan. We are not throwing
        // here, because we did not fail, just the user content is not good for simulation.
        guard !hasError else { return }

        guard simOrder.objects.count == simulationObjects.count else {
            throw InternalSystemError(self,
                                      message: "Unprocessed simulation objects. Expected \(simOrder.objects.count), got \(simulationObjects.count)")
        }

        let boundFlows = try bindFlows(flows, world: world, variables: variables)

        var flowIndices: [ObjectID:Int] = [:]
        for (index, flow) in boundFlows.enumerated() {
            flowIndices[flow.objectID] = index
        }
        
        let boundStocks = try bindStocks(stocks, flowIndices: flowIndices, world: world)
        
        // Simulation parameters
        
        let params: SimulationParameters
        if let simInfo = frame.first(trait: Trait.Simulation) {
            params = SimulationParameters(fromObject: simInfo)
        }
        else {
            params = SimulationParameters()
        }

        
        let plan = SimulationPlan(
            simulationObjects: simulationObjects,
            stateVariables: variables.variables,
            builtins: builtins,
            stocks: boundStocks,
            flows: boundFlows,
//            charts: [], // FIXME: Relic from the past, remove
            valueBindings: [], // FIXME: Relic from the past, remove
            simulationParameters: params
        )
        
        world.setSingleton(plan)
    }
    
    func prepareBuiltins(variables: StateVariableTable) -> BoundBuiltins {
        // 1. Builtins
        let builtins = BoundBuiltins(
            step: variables.allocate(builtin: .step),
            time: variables.allocate(builtin: .time),
            timeDelta: variables.allocate(builtin: .timeDelta)
        )
        
        return builtins
    }
    
    /// Compile an object into its computational representation.
    ///
    /// - Returns: Computational representation of the object or `nil`.
    ///
    /// nil result if:
    ///
    /// - missing required component
    /// - missing required attribute
    ///
    func compileObject(_ object: ObjectSnapshot,
                       world: World,
                       variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation {
        // FIXME: Precompute representation type (and add rep.type type) in sim ordering
        let rep: ComputationalRepresentation
        if object.type.hasTrait(Trait.Formula) {
            rep = try compileFormulaObject(object, world: world, variables: variables)
        }
        else if object.type.hasTrait(Trait.GraphicalFunction) {
            rep = try compileGraphicalFunctionNode(object, world: world, variables: variables)
        }
        else if object.type.hasTrait(Trait.Delay) {
            rep = try compileDelayNode(object, world: world, variables: variables)
        }
        else if object.type.hasTrait(Trait.Smooth) {
            rep = try compileSmoothNode(object, world: world, variables: variables)
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
    func compileFormulaObject(_ object: ObjectSnapshot,
                              world: World,
                              variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation
    
    {
        guard let component: ParsedExpressionComponent = world.component(for: object.objectID) else {
            throw .missingComponent("ParsedExpressionComponent")
        }
        let expression = component.expression
        
        // Finally bind the expression.
        //
        let boundExpression: BoundExpression
        do {
            boundExpression = try bindExpression(expression,
                                                 variables: variables,
                                                 functions: self.builtinFunctions)
        }
        catch /* ExpressionError */ {
            let issue = Issue(
                identifier: "expression_error",
                severity: .error,
                system: self,
                error: error,
                details: [
                    "attribute": "formula",
                    "underlying_error": Variant(error.description),
                ]
            )

            world.appendIssue(issue, for: object.objectID)
            throw .objectIssue
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
    func compileGraphicalFunctionNode(_ object: ObjectSnapshot,
                                      world: World,
                                      variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation {
        let points:[Point] = object["graphical_function_points", default: []]
        let methodName: String = object["interpolation_method",
                                        default: GraphicalFunction.InterpolationMethod.defaultMethod.rawValue]
            
        let method = GraphicalFunction.InterpolationMethod(rawValue: methodName)
                        ?? GraphicalFunction.InterpolationMethod.defaultMethod

        let function = GraphicalFunction(points: points, method: method)
        
        guard let paramComp: ResolvedParametersComponent = world.component(for: object.objectID),
              paramComp.connectedUnnamed.count == 1,
              let parameterID = paramComp.connectedUnnamed.first
        else {
            throw .objectIssue
        }

        guard let paramIndex = variables.index(parameterID) else {
            throw .corruptedState("Invalid variable index)")
        }
        
        let boundFunc = BoundGraphicalFunction(function: function, parameterIndex: paramIndex)
        return .graphicalFunction(boundFunc)
    }
   
    public func compileDelayNode(_ object: ObjectSnapshot,
                                 world: World,
                                 variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation {

        // TODO: What to do if the input is not numeric or not an atom?
        let queueIndex = variables.allocate(
            content: .internalState(object.objectID),
            valueType: .doubles,
            name: "delay_queue_\(object.objectID)"
        )
        
        let initialValueIndex = variables.allocate(
            content: .internalState(object.objectID),
            valueType: .double,
            name: "delay_init_\(object.objectID)"
        )

        guard let paramComp: ResolvedParametersComponent = world.component(for: object.objectID),
              paramComp.connectedUnnamed.count == 1,
              let parameterID = paramComp.connectedUnnamed.first
        else {
            throw .objectIssue
        }

        guard let parameterIndex = variables.index(parameterID) else {
            throw .corruptedState("Invalid variable index)")
        }
        // FIXME: Store defaults somewhere. We should have values here anyways.
        let duration: UInt = object["delay_duration", default: 1]
        let initialValue: Variant? = object["initial_value"]
        
        guard let type = variables.valueType(at: parameterIndex),
              case let .atom(atomType) = type
        else {
            let issue = Issue(
                identifier: "invalid_parameter_type",
                severity: .error,
                system: self,
                error: ModelError.invalidParameterType,
                relatedObjects: [parameterID]
                )
            world.appendIssue(issue, for: object.objectID)
            throw .objectIssue
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
    public func compileSmoothNode(_ object: ObjectSnapshot,
                                 world: World,
                                 variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation {
        let smoothValueIndex = variables.allocate(
            content: .internalState(object.objectID),
            valueType: .doubles,
            name: "smooth_value_\(object.objectID)"
        )
        
        guard let paramComp: ResolvedParametersComponent = world.component(for: object.objectID),
              paramComp.connectedUnnamed.count == 1,
              let parameterID = paramComp.connectedUnnamed.first
        else {
            throw .objectIssue
        }

        guard let parameterIndex = variables.index(parameterID) else {
            throw .corruptedState("Invalid variable index)")
        }
        
        guard let type = variables.valueType(at: parameterIndex),
              case .atom(_) = type
        else {
            let issue = Issue(
                identifier: "invalid_parameter_type",
                severity: .error,
                system: self,
                error: ModelError.invalidParameterType,
                relatedObjects: [parameterID]
                )
            world.appendIssue(issue, for: object.objectID)
            throw .objectIssue
        }

        // FIXME: [REFACTORING] Require the attribute, do not assume the default here
        // This requires attribute error
        let windowTime: Double = object["window_time", default: 1]
        
        let compiled = BoundSmooth(
            windowTime: windowTime,
            smoothValueIndex: smoothValueIndex,
            inputValueIndex: parameterIndex
        )
        
        return .smooth(compiled)
    }


    // MARK: - Flow
    
    func bindFlows(_ flows: [SimulationObject], world: World, variables: StateVariableTable)
    throws (InternalSystemError) -> [BoundFlow] {
        var boundFlows: [BoundFlow] = []
        
        for flow in flows {
            let boundFlow: BoundFlow
            boundFlow = try bindFlow(flow.objectID,
                                     name: flow.name,
                                     valueType: flow.valueType,
                                     variables: variables,
                                     world: world)
            boundFlows.append(boundFlow)
        }
        return boundFlows

    }
    
    func bindFlow(_ objectID: ObjectID,
                  name: String,
                  valueType: ValueType, // rep.valueType
                  variables: StateVariableTable,
                  world: World)
    throws (InternalSystemError) -> BoundFlow {
        guard let component: FlowRateComponent = world.component(for: objectID) else {
            throw InternalSystemError(self,
                                      message: "Missing required component",
                                      context: .frameComponent("FlowRateComponent"))
        }
        guard let objectIndex = variables.objectIndex[objectID] else {
            // TODO: Throw corrupted component
            preconditionFailure()
        }
        let actualIndex = variables.allocate(content: .adjustedResult(objectID),
                                              valueType: valueType,
                                              name:  name)
        let boundFlow = BoundFlow(objectID: objectID,
                                  estimatedValueIndex: objectIndex,
                                  adjustedValueIndex: actualIndex,
                                  priority: component.priority,
                                  drains: component.drainsStock,
                                  fills: component.fillsStock)

        return boundFlow
    }
    
    /// Bind stocks with their variables.
    ///
    func bindStocks(_ stocks: [SimulationObject],
                    flowIndices: [ObjectID:Int], // Index into list of flows
                    world: World)
    throws (InternalSystemError) -> [BoundStock] {
        var result: [BoundStock] = []
        
        for stock in stocks {
            let boundStock: BoundStock
            boundStock = try bindStock(stock.objectID,
                                       variableIndex: stock.variableIndex,
                                       flowIndices: flowIndices,
                                       world: world)
            result.append(boundStock)
        }
        return result
    }
    
    func bindStock(_ objectID: ObjectID,
                   variableIndex: Int,
                   flowIndices: [ObjectID:Int], // Index into list of flows
                   world: World)
    throws (InternalSystemError) -> BoundStock {
        guard let comp: StockComponent = world.component(for: objectID) else {
            throw InternalSystemError(self,
                                      message: "Missing component",
                                      context: .frameComponent("StockDependencyComponent"))
        }

        let inflowIndices = comp.inflowRates.compactMap { flowIndices[$0] }
        let outflowIndices = comp.outflowRates.compactMap { flowIndices[$0] }

        guard inflowIndices.count == comp.inflowRates.count &&
                outflowIndices.count == comp.outflowRates.count
        else {
            throw InternalSystemError(self,
                                      message: "Corrupted component",
                                      context: .frameComponent("StockDependencyComponent"))
        }
        
        let boundStock = BoundStock(
            objectID: objectID,
            variableIndex: variableIndex,
            allowsNegative: comp.allowsNegative,
            inflows: inflowIndices,
            outflows: outflowIndices
        )
        
        return boundStock

    }
}

