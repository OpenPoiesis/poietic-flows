//
//  ObjectIssue.swift
//  
//
//  Created by Stefan Urbanek on 05/01/2023.
//

import PoieticCore

/// An issue detected by the compiler.
///
///
/// - SeeAlso: ``Compiler/issues``, ``Compiler/issues(for:)``, ``Compiler/hasIssues``, ``Compiler/compile()``
///
public enum ObjectIssue: Equatable, CustomStringConvertible, Error {
    /// An error caused by a syntax error in the formula (arithmetic expression).
    case expressionSyntaxError(ExpressionSyntaxError)
   
    case expressionError(ExpressionError)
    
    /// Parameter connected to a node is not used in the formula.
    case unusedInput(String)
    
    /// Parameter in a formula is not connected from a node.
    ///
    /// All parameters in a formula must have a connection from a node
    /// that represents the parameter. This requirement is to make sure
    /// that the model is transparent to the human readers.
    ///
    case unknownParameter(String)
    
    /// The node has the same name as some other node.
    case duplicateName(String)
    
    /// Invalid value for a given attribute
    case invalidAttributeValue(String, Variant)

    /// The node has the same name as some other node.
    case emptyName

    /// Missing a connection from a parameter node to a graphical function.
    case missingRequiredParameter
    
    /// Node is part of a computation cycle.
    case computationCycle
    
    case unsupportedDelayValueType(ValueType)
    
    /// Get the human-readable description of the issue.
    public var description: String {
        switch self {
        case .expressionSyntaxError(let error):
            return "The formula contains a syntax error (\(error))"
        case .expressionError(let error):
            return "The formula contains an error (\(error))"
        case .invalidAttributeValue(let attribute, let value):
            return "Invalid value for attribute '\(attribute)': \(value)"
        case .unusedInput(let name):
            return "Parameter '\(name)' is connected but not used"
        case .unknownParameter(let name):
            return "Parameter '\(name)' is unknown or not connected"
        case .duplicateName(let name):
            return "Duplicate node name: '\(name)'"
        case .emptyName:
            return "Node name is empty"
        case .missingRequiredParameter:
            return "Node is missing a required parameter connection"
        case .computationCycle:
            return "Node is part of a computation cycle"
        case .unsupportedDelayValueType(let type):
            return "Unsupported delay value type: \(type)"
        }
    }
    
    /// Hint for an error.
    ///
    /// If it is possible to get some help to the user how to deal with the
    /// error, then this property provides a hint.
    ///
    public var hint: String? {
        switch self {
        case .expressionSyntaxError(_):
            return "Check the formula syntax"
        case .expressionError(_):
            return "Check the variables, types and functions in the formula and consult the manual for list of available variables and functions."
        case .invalidAttributeValue(_, _):
            return "Check the attribute documentation for allowed values"
        case .unusedInput(let name):
            return "Use the connected parameter or disconnect the node '\(name)'."
        case .unknownParameter(let name):
            return "Connect the parameter node '\(name)'; or check the formula for typos; or remove the parameter from the formula."
        case .duplicateName(_):
            return nil
        case .emptyName:
            return "Set a node name"
        case .missingRequiredParameter:
            return "Connect exactly one node as a parameter. Name does not matter."
        case .computationCycle:
            return "Follow connections from and to the offending node."
        case .unsupportedDelayValueType(_):
            return "Delay can use only atom types, no array types"
        }
    }
}

extension ObjectIssue: DesignIssueConvertible {
    public func asDesignIssue() -> PoieticCore.DesignIssue {
        switch self {
        case .expressionSyntaxError(let error):
            // TODO: Make ExpressionError DesignIssueConvertible
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "syntax_error",
                        message: description,
                        hint: hint,
                        details: [
                            "attribute": "formula",
                            "underlying_error": Variant(error.description),
                            // TODO: Add text location, name
                        ])
        case .expressionError(let error):
            // TODO: Make ExpressionError DesignIssueConvertible
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "expression_error",
                        message: description,
                        hint: hint,
                        details: [
                            "attribute": "formula",
                            "underlying_error": Variant(error.description),
                            // TODO: Add text location, name
                        ])
        case .invalidAttributeValue(let attribute, let value):
            // TODO: Make ExpressionError DesignIssueConvertible
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "invalid_attribute_value",
                        message: description,
                        hint: hint,
                        details: [
                            "attribute": Variant(attribute),
                            "value": value,
                        ])
        case .unusedInput(let name):
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "unused_input",
                        message: description,
                        hint: hint,
                        details: [
                            "name": Variant(name),
                        ])
        case .unknownParameter(let name):
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "unknown_parameter",
                        message: description,
                        hint: hint,
                        details: [
                            "name": Variant(name),
                        ])
        case .duplicateName(let name):
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "duplicate_name",
                        message: description,
                        hint: hint,
                        details: [
                            "attribute": "name",
                            "name": Variant(name),
                        ])
        case .emptyName:
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "empty_name",
                        message: description,
                        hint: hint,
                        details: [
                            "attribute": "name"
                        ])
        case .missingRequiredParameter:
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "missing_parameter",
                        message: description,
                        hint: hint)
        case .computationCycle:
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "computation_cycle",
                        message: description,
                        hint: hint)
        case .unsupportedDelayValueType(let type):
            DesignIssue(domain: .compilation,
                        severity: .error,
                        identifier: "unsupported_value_type",
                        message: description,
                        hint: hint,
                        details: [
                            "type": Variant(type.description),
                        ])
        }
    }
}
