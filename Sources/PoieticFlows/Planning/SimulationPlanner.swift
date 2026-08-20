//
//  SimulationPlanner.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 20/08/2026.
//

import PoieticCore

/// Error thrown during the simulation planning process
public enum PlanningError: Error, Equatable {
    /// Issue with object has been detected, appended to the list of issues. The caller might
    /// continue with the operation to gather more issues. Criticality of this error is
    /// problem specific.
    case userIssue
    
    case corruptedVariableTable
    
    /// Design object does not have content as required. This indicated that the design was
    /// not properly validated against ``StockFlowMetamodel``.
    ///
    case invalidObject(ObjectID, String)
    /// Missing required component. Probably the dependency was not satisfied.
    case missingComponent(ObjectID, String)
    case corruptedComponent(ObjectID, String)
    case unprocessedObjects
}


extension PlanningError {
    func internalSystemErrorContext() -> InternalSystemError.Context {
        let context: InternalSystemError.Context
        switch self {
        case .corruptedComponent(let id, let name):
            context = .component(id, name)
        case .corruptedVariableTable:
            context = .none
        case .invalidObject(let id, _):
            context = .object(id)
        case .missingComponent(let id, let name):
            context = .component(id, name)
        case .unprocessedObjects:
            context = .singleton("SimulationOrder")
        case .userIssue:
            context = .none
        }
        return context
    }
}

/// Object that plans a computation.
///
public class SimulationPlanner {
    public static let IssueSourceName: String = "SimulationPlanner"
    var variables: StateVariableTable
    
    public init() {
        variables = StateVariableTable()
    }
    
    /// Create a simulation plan for specified objects.
    ///
    /// - Parameters:
    ///     - order: Simulation objects ordered by their computational dependencies.
    ///       Created by the ``ComputationOrderSystem``.
    ///     - world: World for which the plan is being created.
    ///
    /// Requirements for the world:
    ///
    /// - Must contain entities for every design object in the `order`
    /// - Entities must have components that correspond to their type, as produced by the analytical
    ///   systems before planning.
    ///
    /// Side-effect: The function attaches ``HasNumericIndicator`` component on entities with
    /// numeric value.
    ///
    /// - Important: The objects are expected to be ordered by their computational dependency. If they are not
    ///   ordered, the simulation result is undefined.
    ///
    /// - Throws: ``PlanningError``. Any other value except ``PlanningError/userIssue`` means
    ///   a programming error.
    ///
    public func createPlan(order simulationOrder: SimulationOrder, in world: World)
    throws (PlanningError) -> SimulationPlan
    {
        var hasError: Bool = false
        var simulationObjects: [SimulationObject] = []
        var flows: [SimulationObject] = []
        var stocks: [SimulationObject] = []

        let builtins = prepareBuiltins()

        for object in simulationOrder.objects {
            guard let entity = world.entity(object.objectID),
                  let nameComp: SimulationName = entity.component(),
                  let role: SimulationRole = entity.component()
            else {
                hasError = true
                continue
            }
            
            let rep: ComputationalRepresentation

            do {
                rep = try compileObject(object, entity: entity)
            }
            catch .userIssue { // Collect all the user issues.
                hasError = true
                continue
            }

            let index = variables.allocate(content: .object(object.objectID),
                                           valueType: rep.valueType,
                                           name: nameComp.name)
            
            let sim = SimulationObject(objectID: object.objectID,
                                       computation: rep,
                                       variableIndex: index,
                                       role: role,
                                       valueType: rep.valueType,
                                       name: nameComp.name)
       
            simulationObjects.append(sim)

            // TODO: This should be responsibility of the system. Planner should just return a plan.
            // In the system (caller) loop through plan.unprocessedObjects and set the component for them
            entity.setComponent(HasNumericIndicator())
            
            switch role {
            case .flow: flows.append(sim)
            case .stock: stocks.append(sim)
            default: break
            }
        }

        // If we have errors, finish early without creating the final plan.
        guard !hasError else { throw .userIssue }

        /// Verify that all objects are processed
        guard simulationOrder.objects.count == simulationObjects.count else {
            throw .unprocessedObjects
        }

        let boundFlows = try bindFlows(flows, world: world)

        var flowIndices: [ObjectID:Int] = [:]
        for (index, flow) in boundFlows.enumerated() {
            flowIndices[flow.objectID] = index
        }
        
        let boundStocks = try bindStocks(stocks, flowIndices: flowIndices, world: world)
        
        let plan = SimulationPlan(
            simulationObjects: simulationObjects,
            stateVariables: variables.variables,
            builtins: builtins,
            stocks: boundStocks,
            flows: boundFlows
        )
        
        return plan
    }

    func prepareBuiltins() -> BoundBuiltins {
        let builtins = BoundBuiltins(
            step: variables.allocate(builtin: .step),
            time: variables.allocate(builtin: .time),
            timeDelta: variables.allocate(builtin: .timeDelta)
        )
        
        return builtins
    }
    
    /// Compile an object into its computational representation.
    ///
    /// - Returns: Computational representation of the object.
    /// - Throws: ``CompilationError`` when missing required component or an attribute.
    ///
    func compileObject(_ object: ObjectSnapshot,
                       entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation {
        // FIXME: Precompute representation type (and add rep.type type) in sim ordering
        let rep: ComputationalRepresentation
        if object.type.hasTrait(Trait.Formula) {
            rep = try compileFormulaObject(object, entity: entity)
        }
        else if object.type.hasTrait(Trait.GraphicalFunction) {
            rep = try compileGraphicalFunctionNode(object, entity: entity)
        }
        else if object.type.hasTrait(Trait.Delay) {
            rep = try compileDelayNode(object, entity: entity)
        }
        else if object.type.hasTrait(Trait.Smooth) {
            rep = try compileSmoothNode(object, entity: entity)
        }
        else {
            // HINT: If this error happens, then check one of the the following:
            // - ComputationOrderSystem and SimulationOrderComponent
            // - whether the design object constraints work properly
            // - whether the design metamodel is stock-flows metamodel
            //   and that it has necessary traits
            //
            throw .invalidObject(object.objectID, "Unknown simulation object type " + object.type.name)
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
    /// - Throws: ``PlanningError`` if there is an issue with parameters,
    ///   function names or other variable names in the expression.
    ///
    func compileFormulaObject(_ object: ObjectSnapshot, entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation
    {
        guard let component: ParsedExpressionComponent = entity.component() else {
            throw .missingComponent(object.objectID, "ParsedExpressionComponent")
        }
        let expression = component.expression
        
        // Finally bind the expression.
        //
        let boundExpression: BoundExpression
        do {
            boundExpression = try Evaluator.bind(expression, variables: variables)
        }
        catch /* ExpressionError */ {
            var details = error.details
            details["attribute"] = "formula"
            let issue = Issue(
                identifier: error.issueIdentifier,
                severity: .error,
                source: Self.IssueSourceName,
                message: error.message,
                hints: error.hints,
                details: details,
            )

            entity.appendIssue(issue)
            throw .userIssue
        }
        
        return .formula(boundExpression)
    }
    
    /// Compiles a graphical function.
    ///
    /// This method creates a bound graphical function object with a single argument and a
    /// numeric return value. The function will compute the output based on the
    /// input parameter and on specifics of the graphical function points
    /// interpolation.
    ///
    /// - Requires: node
    /// - Throws: ``NodeIssue`` if the function parameter is not connected.
    ///
    /// - SeeAlso: ``BoundGraphicalFunction``, ``Solver/evaluate(objectAt:with:)``
    ///
    func compileGraphicalFunctionNode(_ object: ObjectSnapshot, entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation
    {
        let points:[Point] = object["graphical_function_points", default: []]
        let methodName: String = object["interpolation_method",
                                        default: GraphicalFunction.InterpolationMethod.defaultMethod.rawValue]
            
        let method = GraphicalFunction.InterpolationMethod(rawValue: methodName)
                        ?? GraphicalFunction.InterpolationMethod.defaultMethod

        let function = GraphicalFunction(points: points, method: method)
        
        guard let paramComp: ResolvedParameters = entity.component(),
              paramComp.connectedUnnamed.count == 1,
              let parameterID = paramComp.connectedUnnamed.first
        else { throw .userIssue }

        guard let paramIndex = variables.index(parameterID) else {
            throw .corruptedVariableTable
        }
        
        let boundFunc = BoundGraphicalFunction(function: function, parameterIndex: paramIndex)
        return .graphicalFunction(boundFunc)
    }
   
    func compileDelayNode(_ object: ObjectSnapshot, entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation
    {
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

        guard let paramComp: ResolvedParameters = entity.component(),
              paramComp.connectedUnnamed.count == 1,
              let parameterID = paramComp.connectedUnnamed.first
        else { throw .userIssue }

        guard let parameterIndex = variables.index(parameterID) else {
            throw .corruptedVariableTable
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
                source: Self.IssueSourceName,
                message: "Invalid parameter type",
                relatedObjects: [parameterID]
            )
            entity.appendIssue(issue)
            throw .userIssue
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
    func compileSmoothNode(_ object: ObjectSnapshot, entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation
    {
        let smoothValueIndex = variables.allocate(
            content: .internalState(object.objectID),
            valueType: .doubles,
            name: "smooth_value_\(object.objectID)"
        )
        
        guard let paramComp: ResolvedParameters = entity.component(),
              paramComp.connectedUnnamed.count == 1,
              let parameterID = paramComp.connectedUnnamed.first
        else { throw .userIssue }

        guard let parameterIndex = variables.index(parameterID) else {
            throw .corruptedVariableTable
        }
        
        guard let type = variables.valueType(at: parameterIndex),
              case .atom(_) = type
        else {
            let issue = Issue(
                identifier: "invalid_parameter_type",
                severity: .error,
                source: Self.IssueSourceName,
                message: "Invalid parameter type",
                relatedObjects: [parameterID]
            )
            entity.appendIssue(issue)
            throw .userIssue
        }

        // TODO: Require the attribute, do not assume the default here?
        // This requires attribute error
        let windowTime: Double = object["window_time", default: 1]
        
        let compiled = BoundSmooth(
            windowTime: windowTime,
            smoothValueIndex: smoothValueIndex,
            inputValueIndex: parameterIndex
        )
        
        return .smooth(compiled)
    }


    // MARK: - Binding of stocks and flows
    func bindFlows(_ flows: [SimulationObject], world: World)
    throws (PlanningError) -> [BoundFlow]
    {
        var boundFlows: [BoundFlow] = []
        
        for flow in flows {
            guard let entity = world.entity(flow.objectID),
                  let component: FlowRateComponent = entity.component()
            else {
                throw .missingComponent(flow.objectID, "FlowRateComponent")
            }
            guard let estimatedValueIndex = variables.objectIndex[flow.objectID] else {
                throw .corruptedVariableTable
            }
            let adjustedValueIndex = variables.allocate(
                content: .adjustedResult(flow.objectID),
                valueType: flow.valueType,
                name:  "flow_adjusted_\(flow.objectID)"
            )

            // Adjusted: rate actually applied after non-negative-stock scaling
            // Estimated: rate as computed by the flow's formula
            
            let boundFlow = BoundFlow(objectID: flow.objectID,
                                      estimatedValueIndex: estimatedValueIndex,
                                      adjustedValueIndex: adjustedValueIndex,
                                      drains: component.drainsStock,
                                      fills: component.fillsStock)

            boundFlows.append(boundFlow)
        }

        return boundFlows
   }
    
    /// Bind stocks with their variables.
    ///
    func bindStocks(_ stocks: [SimulationObject],
                    flowIndices: [ObjectID:Int], // Index into list of flows
                    world: World)
    throws (PlanningError) -> [BoundStock]
    {
        var result: [BoundStock] = []
        
        for stock in stocks {
            guard let entity = world.entity(stock.objectID),
                  let component: StockComponent = entity.component()
            else {
                throw .missingComponent(stock.objectID, "StockComponent")
            }

            let inflowIndices = component.inflowRates.compactMap { flowIndices[$0] }
            let outflowIndices = component.outflowRates.compactMap { flowIndices[$0] }

            guard inflowIndices.count == component.inflowRates.count &&
                    outflowIndices.count == component.outflowRates.count
            else {
                throw .corruptedComponent(stock.objectID, "StockComponent")
            }
            
            let boundStock = BoundStock(
                objectID: stock.objectID,
                variableIndex: stock.variableIndex,
                allowsNegative: component.allowsNegative,
                inflows: inflowIndices,
                outflows: outflowIndices
            )

            result.append(boundStock)
        }
        
        return result
    }
}
