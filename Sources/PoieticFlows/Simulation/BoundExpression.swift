//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 07/03/2024.
//

import PoieticCore

// FIXME: Why do we need value type if we have index?
public struct BoundVariable: CustomStringConvertible {
    let index: SimulationState.Index
    let valueType: ValueType
    
    public var description: String { "BoundVariable(\(index),\(valueType))" }
}
public typealias BoundExpression = ArithmeticExpression<BoundVariable, Function>

extension BoundExpression {
    public var valueType: ValueType {
        switch self {
        case let .value(value): return value.valueType
        case let .variable(variable): return variable.valueType
        case let .unary(function, _): return function.signature.returnType
        case let .binary(function, _, _): return function.signature.returnType
        case let .function(function, _): return function.signature.returnType
        }
    }
}


// TODO: Make ExpressionError DesignIssueConvertible
public enum ExpressionError: Error, CustomStringConvertible, Equatable {
    case unknownVariable(String)
    case unknownFunction(String)
    case invalidNumberOfArguments(Int, Int)
    // TODO: Add argument name
    case argumentTypeMismatch(Int, String)
    
    public var description: String {
        switch self {
        case let .unknownVariable(name):
            "Unknown variable '\(name)'"
        case let .unknownFunction(name):
            "Unknown function '\(name)'"
        case .invalidNumberOfArguments:
            "Invalid number of arguments"
        case let .argumentTypeMismatch(number, expected):
            "Invalid type of argument number \(number). Expected: \(expected)"
        }
    }
}

extension ExpressionError: IssueProtocol {
    public var message: String { "Formula error: " + description }
    public var hints: [String] { ["Check the variables, types and functions in the formula and consult the manual for list of available variables and functions."] }
    
}

/// Bind an expression to concrete variable references.
///
/// - Parameters:
///     - expression: Unbound arithmetic expression, where the function and
///       variable references are strings.
///     - variables: List of compiled state variables.
///     - names: Dictionary of variables where the keys are variable names
///       and the values are (bound) references to the variables.
///     - functions: Dictionary of functions and operators where the keys are
///       function names and the values are objects representing functions.
///       See the list below of special function names that represent operators.
///
/// The operators are functions with special names. The following list contains
/// the names of the operators:
///
/// - `__add__` – binary addition operator `+`
/// - `__sub__` – binary subtraction operator `-`
/// - `__mul__` – binary multiplication operator `*`
/// - `__div__` – binary division operator `/`
/// - `__mod__` – binary modulo operator `%`
/// - `__neg__` – unary negation operator `-`
/// - `__exp__` – binary exponent operator `^`
///
/// - Note: The operator names are similar to the operator method names in
///   Python.
///
/// - Returns: ``PoieticCore/ArithmeticExpression`` where variables and functions are resolved.
/// - Throws: ``ExpressionError`` when a variable or a function is not known
///  or when the function arguments do not match the function's requirements.
///
public func bindExpression(_ expression: UnboundExpression,
                           variables: [StateVariable],
                           names: [String:SimulationState.Index],
                           functions: [String:Function]) throws (ExpressionError) -> BoundExpression {
    
    switch expression {
    case let .value(value):
        return .value(value)

    case let .variable(name):
        guard let index = names[name] else {
            throw ExpressionError.unknownVariable(name)
        }
        let variable = variables[index]
        return .variable(BoundVariable(index: index,
                                       valueType: variable.valueType))
    case let .unary(op, operand):
        let funcName: String = switch op {
        case "-": "__neg__"
        default: fatalError("Unknown unary operator: '\(op)'. Hint: check the expression parser.")
        }

        guard let function = functions[funcName] else {
            fatalError("No function '\(funcName)' for unary operator: '\(op)'. Hint: Make sure it is defined in the builtin function list.")
        }

        let boundOperand = try bindExpression(operand,
                                              variables: variables,
                                              names: names,
                                              functions: functions)
        
        let result = function.signature.validate([boundOperand.valueType])
        switch result {
        case .invalidNumberOfArguments:
            throw ExpressionError.invalidNumberOfArguments(1,
                                                         function.signature.minimalArgumentCount)
        case .typeMismatch(_):
            throw ExpressionError.argumentTypeMismatch(1, "int or double")
        default:
            return .unary(function, boundOperand)
        }
        
        
    case let .binary(op, lhs, rhs):
        let funcName: String = switch op {
        case "+": "__add__"
        case "-": "__sub__"
        case "*": "__mul__"
        case "/": "__div__"
        case "%": "__mod__"
        case "^": "__pow__"
        // Comparison
        case "==": "__eq__"
        case "!=": "__ne__"
        case "<" : "__lt__"
        case "<=": "__le__"
        case ">" : "__gt__"
        case ">=": "__ge__"
        default: fatalError("Unknown binary operator: '\(op)'. Internal hint: check the expression parser.")
        }
        
        guard let function = functions[funcName] else {
            fatalError("No function '\(funcName)' for binary operator: '\(op)'. Internal hint: Make sure it is defined in the builtin function list.")
        }

        let lBound = try bindExpression(lhs,
                                        variables: variables,
                                        names: names,
                                        functions: functions)
        let rBound = try bindExpression(rhs,
                                        variables: variables,
                                        names: names,
                                        functions: functions)

        let args = [lBound.valueType, rBound.valueType]
        let result = function.signature.validate(args)
        switch result {
        case .invalidNumberOfArguments:
            throw ExpressionError.invalidNumberOfArguments(2,
                                                         function.signature.minimalArgumentCount)
        case .typeMismatch(let index):
            // TODO: We need all indices
            throw ExpressionError.argumentTypeMismatch(index.first! + 1, String(describing: function.signature.returnType))
        default: //
            return .binary(function, lBound, rBound)
        }

    case let .function(name, arguments):
        guard let function = functions[name] else {
            throw ExpressionError.unknownFunction(name)
        }
        
        var boundArgs: [BoundExpression] = []
        
        // NOTE: arguments.map(...) has no typed throw (Swift 6.0)
        for arg in arguments {
            let boundArg = try bindExpression(arg,
                                              variables: variables,
                                              names: names,
                                              functions: functions)
            boundArgs.append(boundArg)
        }

        let types = boundArgs.map { $0.valueType }
        let result = function.signature.validate(types)

        switch result {
        case .invalidNumberOfArguments:
            throw ExpressionError.invalidNumberOfArguments(arguments.count,
                                          function.signature.minimalArgumentCount)
        case .typeMismatch(let index):
            // TODO: We need all indices
            throw ExpressionError.argumentTypeMismatch(index.first! + 1, "int or double")
        default: //
            return .function(function, boundArgs)
        }
    }
}

// FIXME: [REFACTORING] [SYSTEMS] Use this one instead of the one above.
func bindExpression(_ expression: UnboundExpression,
                    variables: StateVariableTable,
                    functions: [String:Function])
throws (ExpressionError) -> BoundExpression
{
    switch expression {
    case let .value(value):
        return .value(value)

    case let .variable(name):
        guard let variable: StateVariable = variables[name] else {
            throw ExpressionError.unknownVariable(name)
        }
        return .variable(BoundVariable(index: variable.index,
                                       valueType: variable.valueType))
    case let .unary(op, operand):
        let funcName: String = switch op {
        case "-": "__neg__"
        default: fatalError("Unknown unary operator: '\(op)'. Hint: check the expression parser.")
        }

        guard let function = functions[funcName] else {
            fatalError("No function '\(funcName)' for unary operator: '\(op)'. Hint: Make sure it is defined in the builtin function list.")
        }

        let boundOperand = try bindExpression(operand, variables: variables, functions: functions)
        
        let result = function.signature.validate([boundOperand.valueType])
        switch result {
        case .invalidNumberOfArguments:
            throw .invalidNumberOfArguments(1,
                                                         function.signature.minimalArgumentCount)
        case .typeMismatch(_):
            throw .argumentTypeMismatch(1, "int or double")
        default:
            return .unary(function, boundOperand)
        }
        
        
    case let .binary(op, lhs, rhs):
        let funcName: String = switch op {
        case "+": "__add__"
        case "-": "__sub__"
        case "*": "__mul__"
        case "/": "__div__"
        case "%": "__mod__"
        case "^": "__pow__"
        // Comparison
        case "==": "__eq__"
        case "!=": "__ne__"
        case "<" : "__lt__"
        case "<=": "__le__"
        case ">" : "__gt__"
        case ">=": "__ge__"
        default: fatalError("Unknown binary operator: '\(op)'. Internal hint: check the expression parser.")
        }
        
        guard let function = functions[funcName] else {
            fatalError("No function '\(funcName)' for binary operator: '\(op)'. Internal hint: Make sure it is defined in the builtin function list.")
        }

        let lBound = try bindExpression(lhs, variables: variables, functions: functions)
        let rBound = try bindExpression(rhs, variables: variables, functions: functions)

        let args = [lBound.valueType, rBound.valueType]
        let result = function.signature.validate(args)
        switch result {
        case .invalidNumberOfArguments:
            throw ExpressionError.invalidNumberOfArguments(2,
                                                         function.signature.minimalArgumentCount)
        case .typeMismatch(let index):
            // TODO: We need all indices
            throw ExpressionError.argumentTypeMismatch(index[0] + 1, String(describing: function.signature.returnType))
        default: //
            return .binary(function, lBound, rBound)
        }

    case let .function(name, arguments):
        guard let function = functions[name] else {
            throw ExpressionError.unknownFunction(name)
        }
        
        var boundArgs: [BoundExpression] = []
        
        for arg in arguments {
            let boundArg = try bindExpression(arg, variables: variables, functions: functions)
            boundArgs.append(boundArg)
        }

        let types = boundArgs.map { $0.valueType }
        let result = function.signature.validate(types)

        switch result {
        case .invalidNumberOfArguments:
            throw ExpressionError.invalidNumberOfArguments(arguments.count,
                                          function.signature.minimalArgumentCount)
        case .typeMismatch(let index):
            // TODO: We need all indices
            throw ExpressionError.argumentTypeMismatch(index[0] + 1, "int or double")
        default: //
            return .function(function, boundArgs)
        }
    }
}

