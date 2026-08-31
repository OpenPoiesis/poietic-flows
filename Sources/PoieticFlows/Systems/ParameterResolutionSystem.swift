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
            
            let required = Self.requiredParameters(in: expression, excludeKeys: builtinKeys)
            let incoming = plane.incoming(objectID)
                            .filter { $0.object.type === ObjectType.Parameter }
                            .map { $0.origin }

            let connections = Self.resolveConnections(incoming, required: required, in: world)
            
            guard !connections.isEmpty else { continue }

            // Collect issues
            for key in connections.missing {
                guard let displayName = required[key] else { continue }
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

            for item in connections.unused {
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
                connected: connections.connected,
                missing: Array(connections.missing),
                unused: connections.unused.map { $0.origin }
            )
            entity.setComponent(paramComponent)
        }
    }
   
    /// Get required variables from an expression.
    ///
    /// - Returns: A dictionary where keys are normalised name keys and values are names used in
    ///   the formula.
    static func requiredParameters(in expression: ParsedExpressionComponent,
                                   excludeKeys: [String]) -> [String: String]
    {
        // Map: key -> name used in formula
        var requiredParams: [String:String] = [:]
        
        for variable in expression.usedVariables {
            let key = NormalizedName.normalize(variable)
            guard !excludeKeys.contains(key) else { continue }
            requiredParams[key] = variable
        }
        return requiredParams
    }
    
    struct ParameterConnections {
        var connected: [String: ObjectID] = [:]
        var missing: Set<String> = []
        var unused: [(origin: ObjectID, displayName: String)] = []
        var isEmpty: Bool { connected.isEmpty && missing.isEmpty && unused.isEmpty }
    }
    
    /// Resolve parameter connections.
    ///
    /// - Parameters:
    ///     - incoming: List of object IDs that are origins on `Parameter` edges towards object
    ///       being resolved.
    ///     - required: Map of required parameters. Keys are normalised name keys, values
    ///       are display names (as used in their original location).
    ///     - world: World where to resolve parameters in.
    ///
    /// Each object in the `incoming` list is expected to have `NormalizedName` component on it.
    /// Those without it are skipped – treated as missing.
    ///
    static func resolveConnections(_ incoming: [ObjectID],
                                   required: [String: String],
                                   in world: World) -> ParameterConnections
    {
        var connected: [String:ObjectID] = [:]
        var missing: Set<String> = Set(required.keys)
        var unused: [(origin: ObjectID, displayName: String)] = []
        
        for origin in incoming {
            guard let parameterEntity = world.entity(origin),
                  let parameterObjectName: NormalizedName = parameterEntity.component()
            else { continue }
            
            if missing.contains(parameterObjectName.key) {
                missing.remove(parameterObjectName.key)
                connected[parameterObjectName.key] = origin
            }
            else {
                unused.append((origin: origin, displayName: parameterObjectName.displayName))
            }
        }
        
        return ParameterConnections(connected: connected, missing: missing, unused: unused)
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

                component = ResolvedParameters(missingUnnamed: 1)
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

                let unused = incomingParams.map { $0.origin }
                component = ResolvedParameters(unused: unused)
            }
            else { // if incomingParams.count == 1
                component = ResolvedParameters(connectedUnnamed: [incomingParams[0].origin])
            }

            entity.setComponent(component)
        }
    }
}
