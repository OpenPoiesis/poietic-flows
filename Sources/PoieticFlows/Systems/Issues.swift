//
//  DomainIssues.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 04/11/2025.
//

import PoieticCore

/// Collection of issue identifiers that are attached to objects by systems in the PoieticFlows
/// package.
public enum IssueIdentifier {
    public static let unknownParameter = "unknown_parameter"
    public static let unusedInput = "unused_input"
    public static let missingRequiredParameter = "missing_required_parameter"
    public static let tooManyParameters = "too_many_parameters"
    public static let duplicateName = "duplicate_name"
    public static let reservedName = "reserved_name"
    public static let computationCycle = "computation_cycle"
    public static let invalidParameterType = "invalid_parameter_type"
}
