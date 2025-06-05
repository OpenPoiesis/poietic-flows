//
//  Compiler+Auxiliaries.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 18/04/2025.
//

import PoieticCore

extension Compiler {
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
    func compileGraphicalFunctionNode(_ object: ObjectSnapshot) throws (InternalCompilerError) -> ComputationalRepresentation{
        guard let points = try? object["graphical_function_points"]?.pointArray() else {
            throw .attributeExpectationFailure(object.objectID, "graphical_function_points")
        }
        // TODO: Interpolation method
        let function = GraphicalFunction(points: points)
        
        let parameters = view.incomingParameterNodes(object.objectID)
        guard let parameterNode = parameters.first else {
            issues.append(ObjectIssue.missingRequiredParameter, for: object.objectID)
            throw .objectIssue
        }
        
        let boundFunc = BoundGraphicalFunction(function: function,
                                               parameterIndex: objectVariableIndex[parameterNode.objectID]!)
        return .graphicalFunction(boundFunc)
    }
    
    /// Compile a delay node.
    ///
    func compileDelayNode(_ object: ObjectSnapshot) throws (InternalCompilerError) -> ComputationalRepresentation{
        let queueIndex = createStateVariable(content: .internalState(object.objectID),
                                             valueType: .doubles,
                                             name: "delay_queue_\(object.objectID)")
        
        let initialValueIndex = createStateVariable(content: .internalState(object.objectID),
                                                    valueType: .doubles,
                                                    name: "delay_init_\(object.objectID)")
        
        let parameters = view.incomingParameterNodes(object.objectID)
        guard let parameterNode = parameters.first else {
            issues.append(ObjectIssue.missingRequiredParameter, for: object.objectID)
            throw .objectIssue
        }
        
        let parameterIndex = objectVariableIndex[parameterNode.objectID]!
        let variable = stateVariables[parameterIndex]
        
        guard let duration = try? object["delay_duration"]?.intValue() else {
            throw .attributeExpectationFailure(object.objectID, "delay_duration")
        }
        guard let posDuration = UInt(exactly: duration) else {
            issues.append(ObjectIssue.invalidAttributeValue("delay_duration", Variant(duration)), for: object.objectID)
            throw .objectIssue
        }
        
        let initialValue = object["initial_value"]
        
        guard case let .atom(atomType) = variable.valueType else {
            issues.append(.unsupportedDelayValueType(variable.valueType), for: object.objectID)
            throw .objectIssue
        }
        
        // TODO: Check whether the initial value and variable.valueType are the same
        let compiled = BoundDelay(
            steps: posDuration,
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
    func compileSmoothNode(_ object: ObjectSnapshot) throws (InternalCompilerError) -> ComputationalRepresentation{
        let smoothValueIndex = createStateVariable(content: .internalState(object.objectID),
                                                   valueType: .doubles,
                                                   name: "smooth_value_\(object.objectID)")
        
        let parameters = view.incomingParameterNodes(object.objectID)
        guard let parameterNode = parameters.first else {
            issues.append(ObjectIssue.missingRequiredParameter, for: object.objectID)
            throw .objectIssue
        }
        
        let parameterIndex = objectVariableIndex[parameterNode.objectID]!
        let variable = stateVariables[parameterIndex]
        
        guard let windowTime = try? object["window_time"]?.doubleValue() else {
            throw .attributeExpectationFailure(object.objectID, "window_time")
        }
        
        guard case .atom(_) = variable.valueType else {
            issues.append(.unsupportedDelayValueType(variable.valueType), for: object.objectID)
            throw .objectIssue
        }
        
        let compiled = BoundSmooth(
            windowTime: windowTime,
            smoothValueIndex: smoothValueIndex,
            inputValueIndex: parameterIndex
        )
        
        return .smooth(compiled)
    }
    
}
