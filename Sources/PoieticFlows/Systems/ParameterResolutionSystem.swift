//
//  ParameterResolutionSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore

/// Component with information about connected, missing and unused parameters.
///
/// This component can be used for error reporting or for automatic creation of parameter
/// connections.
///
/// - **Created By:** ``ParameterResolutionSystem``
/// - **Used By:**
///     - ``SimulationPlanner`` for single-input parameter nodes such as smooth, delay and
///       graphical function.
///     - ``ParameterConnectionProposalSystem`` for proposing parameter connections or connection
///       removals.
public struct ResolvedParameters: Component {
    internal init(connected: [String : ObjectID] = [:],
                  connectedUnnamed: [ObjectID] = [],
                  missing: [String] = [],
                  missingUnnamed: Int = 0,
                  unused: [ObjectID] = []) {
        self.connected = connected
        self.connectedUnnamed = connectedUnnamed
        self.missing = missing
        self.missingUnnamed = missingUnnamed
        self.unused = unused
    }
    
    /// Connected named parameters.
    ///
    /// The keys are normalised name keys, the values are object IDs of the parameter nodes.
    public let connected: [String:ObjectID]
    /// List of connected parameters where the name is not used, such as parameters
    /// for graphical function, smooth or delay.
    public let connectedUnnamed: [ObjectID]
    /// List of normalised name keys of parameters are not connected.
    public let missing: [String]
    /// Number of missing unnamed parameters
    public let missingUnnamed: Int
    /// List of `Parameter`object type edges that are connected but not used.
    public let unused: [ObjectID]
}

/// Resolve missing and unused parameter connections.
///
/// The Stock and Flow model requires that parameters are connected to the nodes where they are
/// used. The visual representation must match computational representation for human-oriented
/// clarity.
///
/// - **Input:** Nodes with compiled expression in `ParsedExpressionComponent` and objects
/// of auxiliary types: graphical function, smooth or delay.
/// - **Output:** ``ResolvedParameters`` set of each input component
/// - **Forgiveness:** Nothing needed.
/// - **Issues Appended:**
///     - `unknown_parameter`: Parameter in a formula is not connected from a node.
///     - `unused_input`: Parameter connected to a node is not used in the formula.
///     - `missing_required_parameter`: Missing a connection from a parameter node to a graphical
///        function.
///     - `too_many_parameters`: Too many parameters for a node, usually used with single-parameter
///        auxiliaries such as graphical function, delay or smooth.
///
/// - Note: All parameters in a formula must have a connection from a node that represents the
///   parameter. This requirement is to make sure that the model is transparent to the human
///   readers.
///
public struct ParameterResolutionSystem: System {
    public static let IssueSourceName = "ParameterResolutionSystem"

    public static let dependencies: [SystemDependency] = [
        .after(NameNormalizationSystem.self), // Gets us normalised object names
        .after(ExpressionParserSystem.self),  // Gets us required variable names
    ]

    public static func update(_ world: World) throws (InternalSystemError) {
        guard let plane = world.plane else { return }
        try resolveFormulas(world, plane: plane)
        try resolveAuxiliaries(world, plane: plane, type: .GraphicalFunction)
        try resolveAuxiliaries(world, plane: plane, type: .Delay)
        try resolveAuxiliaries(world, plane: plane, type: .Smooth)
    }

    public static func resolveFormulas(_ world: World, plane: DesignPlane) throws (InternalSystemError) {
        let builtinKeys = BuiltinVariable.normalizedKeys

        for (entity, expression) in world.query(ParsedExpressionComponent.self) {
            guard let objectID = entity.objectID else { continue }
            
            // Map: key -> name used in formula
            var requiredParams: [String:String] = [:]
            
            for variable in expression.usedVariables {
                let key = NormalizedName.normalize(variable)
                guard !builtinKeys.contains(key) else { continue }
                requiredParams[key] = variable
            }
            
            let incomingParams = plane.incoming(objectID).filter {
                $0.object.type === ObjectType.Parameter
            }

            var connected: [String:ObjectID] = [:]
            var missing: Set<String> = Set(requiredParams.keys)
            var unused: [(origin: ObjectID, displayName: String)] = []
            
            for edge in incomingParams {
                guard let parameterEntity = world.entity(edge.origin),
                      let parameterObjectName: NormalizedName = parameterEntity.component()
                else { continue }
                
                if missing.contains(parameterObjectName.key) {
                    missing.remove(parameterObjectName.key)
                    connected[parameterObjectName.key] = edge.origin
                }
                else {
                    unused.append((origin: edge.origin, displayName: parameterObjectName.displayName))
                }
            }
            // If no parameters are required or unnecessarily connected, just continue
            guard !(connected.isEmpty && missing.isEmpty && unused.isEmpty) else {
                continue
            }

            // Collect issues
            for key in missing {
                guard let displayName = requiredParams[key] else { continue }
                let issue = Issue(
                    identifier: IssueIdentifier.unknownParameter,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Variable '\(displayName)' is unknown or not connected",
                    hints: [
                        "Connect the parameter node '\(displayName)'",
                        "Check the formula for typos",
                        "Remove the parameter from the formula."
                    ],
                    details: ["parameter": Variant(displayName)]
                    )
                entity.appendIssue(issue)
            }

            for item in unused {
                let issue = Issue(
                    identifier: IssueIdentifier.unusedInput,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Parameter '\(item.displayName)' is connected but not used",
                    hints: ["Use the connected parameter or disconnect the node '\(item.displayName)'"],
                    details: ["parameter": Variant(item.displayName)],
                    )
                entity.appendIssue(issue)
            }

            let paramComponent = ResolvedParameters(
                connected: connected,
                missing: Array(missing),
                unused: unused.map { $0.origin }
            )
            entity.setComponent(paramComponent)
        }
    }
    /// Resolve connections of single-parameter auxiliaries such as graphical function,
    /// delay or smooth.
    ///
    /// - Requirement: The auxiliary should have one connected parameter.
    ///
    public static func resolveAuxiliaries(_ world: World, plane: DesignPlane, type: ObjectType)
    throws (InternalSystemError) {
        for object in plane.filter(type: type) {
            guard let entity = world.entity(object.objectID) else { continue }
            
            let incomingParams = plane.incoming(object.objectID).filter {
                $0.object.type === ObjectType.Parameter
            }
            let component: ResolvedParameters
            
            if incomingParams.count == 0 {
                let issue = Issue(
                    identifier: IssueIdentifier.missingRequiredParameter,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Missing required parameter connection",
                    hints: [
                        "Connect exactly one other node as a parameter. Name does not matter",
                    ],
                )
                entity.appendIssue(issue)

                component = ResolvedParameters(
                    missingUnnamed: 1
                )
            }
            else if incomingParams.count > 1 {
                let issue = Issue(
                    identifier: IssueIdentifier.tooManyParameters,
                    severity: .error,
                    source: Self.IssueSourceName,
                    message: "Too many parameters connected",
                    hints: [
                        "Keep only required parameter(s), disconnect the others",
                    ]
                )
                entity.appendIssue(issue)

                component = ResolvedParameters(
                    unused: incomingParams.map { $0.origin }
                )
            }
            else { // if incomingParams.count == 1
                component = ResolvedParameters(
                    connectedUnnamed: [incomingParams[0].origin]
                )
            }

            entity.setComponent(component)
        }
    }
}
