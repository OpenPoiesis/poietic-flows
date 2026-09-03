//
//  SimulationPlanner+Compile.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/08/2026.
//

import PoieticCore

extension SimulationPlanner {
    /// Create simulation objects from ordered list of snapshots.
    ///
    func compileObjects(objects: [ObjectSnapshot], in world: World)
    throws (PlanningError) -> [SimulationObject]
    {
        var result: [SimulationObject] = []
        
        for object in objects {
            guard let entity = world.entity(object.objectID) else {
                throw .invalidObject(object.objectID, "No world entity")
            }
            guard !entity.contains(InvalidName.self) else {
                hasError = true
                continue
            }
            guard let nameComp: NormalizedName = entity.component() else {
                 throw .missingComponent(object.objectID, "NormalizedName")
            }
            guard let role: SimulationRole = entity.component() else {
                throw .missingComponent(object.objectID, "SimulationRole")
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
                                           name: nameComp.key)
            
            let sim = SimulationObject(objectID: object.objectID,
                                       computation: rep,
                                       variableIndex: index,
                                       role: role,
                                       valueType: rep.valueType,
                                       nameKey: nameComp.key)
       
            result.append(sim)

            // TODO: This should be responsibility of the system. Planner should just return a plan.
            // In the system (caller) loop through plan.unprocessedObjects and set the component for them
            entity.setComponent(HasNumericIndicator())
        }
        
        return result
    }
    /// Compile an object into its computational representation.
    ///
    /// - Returns: Computational representation of the object.
    /// - Throws: ``PlanningError`` when missing required component or an attribute.
    ///
    func compileObject(_ object: ObjectSnapshot, entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation
    {
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
            // - ComputationOrderSystem and SimulationOrder
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
    ///       `ParsedExpressionComponent`.
    ///
    /// - Precondition: The node must have `ParsedExpressionComponent` associated
    ///   with it.
    ///
    /// - Throws: ``PlanningError`` if there is an issue with parameters,
    ///   function names or other variable names in the expression.
    ///
    func compileFormulaObject(_ object: ObjectSnapshot, entity: RuntimeEntity)
    throws (PlanningError) -> ComputationalRepresentation
    {
        guard let component: ParsedExpressionComponent = entity.component()
        else {
            if entity.hasIssues {
                throw .userIssue
            }
            else {
                throw .missingComponent(object.objectID, "ParsedExpressionComponent")
            }
        }
        let expression = component.expression
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
    /// - Throws: ``PlanningError`` if the function parameter is not connected.
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

        guard let paramRef = variables.reference(parameterID) else {
            throw .corruptedVariableTable
        }
        
        let boundFunc = BoundGraphicalFunction(function: function, parameter: paramRef)
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
                identifier: IssueIdentifier.invalidParameterType,
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
                identifier: IssueIdentifier.invalidParameterType,
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


}
