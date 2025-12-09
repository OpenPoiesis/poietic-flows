//
//  DomainIssues.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 04/11/2025.
//

import PoieticCore

/// Errors representing violations of Stock and Flow model constraints.
///
/// These errors are detected during model analysis and prevent successful
/// simulation planning. They indicate issues with the design model itself,
/// such as structural problems, naming conflicts, or type mismatches.
///
/// Model errors are collected across various analysis systems including:
/// 
/// - Parameter resolution
/// - Name resolution
/// - Computation ordering
/// - Type checking
///
public enum ModelError: IssueProtocol, CustomStringConvertible {
    case expressionError(ExpressionError)
    
    // ## Parameter Resolution
    /// Parameter connected to a node is not used in the formula.
    case unusedInput(String)
    
    /// Parameter in a formula is not connected from a node.
    ///
    /// All parameters in a formula must have a connection from a node
    /// that represents the parameter. This requirement is to make sure
    /// that the model is transparent to the human readers.
    ///
    case unknownParameter(String)

    /// Missing a connection from a parameter node to a graphical function.
    case missingRequiredParameter
    
    /// Too many parameters for a node, usually used with single-parameter auxiliaries
    /// such as graphical function, delay or smooth.
    case tooManyParameters

    /// The node has the same name as some other node.
    case duplicateName(String)

    /// The node's name is empty or contains only whitespace.
    case emptyName

    /// Node is part of a computation cycle.
    case computationCycle
    
    
    // # Object Type Specific
    case invalidParameterType

    /// Get the human-readable description of the issue.
    public var description: String {
        switch self {
        case .expressionError(let error):
            "Formula error: \(error)"
        // ## Parameter Resolution
        case .unknownParameter(let name):
            "Parameter '\(name)' is unknown or not connected"
        case .unusedInput(let name):
            "Parameter '\(name)' is connected but not used"
        case .missingRequiredParameter:
            "Missing required parameter connection"
        case .tooManyParameters:
            "Too many parameters connected"

        case .duplicateName(let name):
            "Duplicate node name: '\(name)'"
        case .emptyName:
            "Node name is empty"

        case .computationCycle:
            "Node is part of a computation cycle"
            
        case .invalidParameterType:
            "Invalid parameter type"
        }
    }
    
    public var message: String { description }
    
    /// Hint for an error.
    ///
    /// If it is possible to get some help to the user how to deal with the
    /// error, then this property provides a hint.
    ///
    public var hints: [String] {
        switch self {
        case .expressionError(_):
            ["Check the variables, types and functions in the formula and consult the manual for list of available variables and functions."]
        case .unusedInput(let name):
            ["Use the connected parameter or disconnect the node '\(name)'."]
        case .unknownParameter(let name):
            [
                "Connect the parameter node '\(name)'",
                "Check the formula for typos",
                "Remove the parameter from the formula."
            ]
        case .missingRequiredParameter:
            [
                "Connect exactly one other node as a parameter. Name does not matter."
            ]
        case .tooManyParameters:
            [
                "Keep only required parameter(s), disconnect the others",
            ]

        case .duplicateName(_): []

        case .emptyName:
            ["Set a node name that is not visually empty"]

        case .computationCycle:
            ["Disconnect at least one of the parameter connections that is causing the cycle."]
        case .invalidParameterType:
            [
                "Check the value type of the parameter node connected to this node",
            ]
        }
    }
}
