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
    /// Object IDs of parameter nodes connected to single-input nodes such as graphical function,
    /// smooth or delay.
    public let connectedUnnamed: [ObjectID]
    /// List of normalised name keys of parameters that are not connected.
    public let missing: [String]
    /// Number of missing unnamed parameters
    public let missingUnnamed: Int
    /// Object IDs of `Parameter` edges that are connected but not used.
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
/// - **Output:** ``ResolvedParameters`` component set on each node with a formula or a
///   single-input auxiliary.
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

    /// Intermediate resolution result.
    ///
    /// - SeeAlso: ``ParameterResolutionSystem/resolveConnections()``
    ///
    struct ResolvedConnections {
        /// Map of parameter key to parameter object ID.
        var connected: [String: ObjectID] = [:]
        /// List of missing parameter keys
        var missing: Set<String> = []
        /// Tuples of unused edges where the displayName is the name of edge's origin.
        var unused: [(edgeID: ObjectID, displayName: String)] = []
        
        var isEmpty: Bool { connected.isEmpty && missing.isEmpty && unused.isEmpty }
    }

    public static let dependencies: [SystemDependency] = [
        .after(NameNormalizationSystem.self), // Gets us normalised object names
        .after(ExpressionParserSystem.self),  // Gets us required variable names
    ]

    public static func update(_ world: World) throws (InternalSystemError) {
        guard let plane = world.plane else { return }
        try resolveFormulas(world, plane: plane)
        try resolveAuxiliaries(world, plane: plane, type: StockFlowDomain.Types.GraphicalFunction)
        try resolveAuxiliaries(world, plane: plane, type: StockFlowDomain.Types.Delay)
        try resolveAuxiliaries(world, plane: plane, type: StockFlowDomain.Types.Smooth)
    }

    public static func resolveFormulas(_ world: World, plane: DesignPlane) throws (InternalSystemError) {
        let builtinKeys = BuiltinVariable.normalizedKeys

        for (entity, expression) in world.query(ParsedExpressionComponent.self) {
            guard let objectID = entity.objectID else { continue }
            
            let required = Self.requiredParameters(in: expression, excludeKeys: builtinKeys)
            var existing: [(parameterID: ObjectID, edgeID: ObjectID)] = []
            
            for edge in plane.incoming(objectID) {
                guard edge.object.type.matches(StockFlowDomain.Types.Parameter) else { continue }
                existing.append((parameterID: edge.origin, edgeID: edge.id))
            }

            let connections = Self.resolveConnections(
                parameters: existing,
                requiredKeys: Set(required.keys),
                in: world
            )
            
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
                unused: connections.unused.map { $0.edgeID }
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
    
    /// Resolve parameter connections.
    ///
    /// - Parameters:
    ///     - parameters: List of tuples describing incoming `Parameter` edges pointing towards the
    ///       object being resolved.
    ///     - requiredKeys: Set of normalised name keys of required parameters.
    ///     - world: World where to resolve parameters in.
    ///
    /// Each parameter object in the `parameters` list is expected to have `NormalizedName`
    /// component on it. Those without it are skipped and the required variable remains missing.
    ///
    static func resolveConnections(parameters: [(parameterID: ObjectID, edgeID: ObjectID)],
                                   requiredKeys: Set<String>,
                                   in world: World) -> ResolvedConnections
    {
        var missing: Set<String> = requiredKeys

        var connected: [String:ObjectID] = [:]
        var unused: [(edgeID: ObjectID, displayName: String)] = []
        
        for (parameterID, edgeID) in parameters {
            guard let parameterEntity = world.entity(parameterID),
                  let parameterName: NormalizedName = parameterEntity.component()
            else { continue }
            
            if missing.contains(parameterName.key) {
                missing.remove(parameterName.key)
                connected[parameterName.key] = parameterID
            }
            else {
                unused.append((edgeID: edgeID, displayName: parameterName.displayName))
            }
        }
        
        return ResolvedConnections(connected: connected, missing: missing, unused: unused)
    }
    
    /// Resolve connections of single-parameter auxiliaries such as graphical function,
    /// delay or smooth.
    ///
    /// - Requirement: The auxiliary should have one connected parameter.
    ///
    public static func resolveAuxiliaries(_ world: World, plane: DesignPlane, type: ObjectType)
    throws (InternalSystemError)
    {
        for object in plane.filter(type: type) {
            guard let entity = world.entity(object.objectID) else { continue }
            
            let incomingParams = plane.incoming(object.objectID).filter {
                $0.object.type.matches(StockFlowDomain.Types.Parameter)
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

                let unused = incomingParams.map { $0.id }
                component = ResolvedParameters(unused: unused)
            }
            else { // if incomingParams.count == 1
                component = ResolvedParameters(connectedUnnamed: [incomingParams[0].origin])
            }

            entity.setComponent(component)
        }
    }
}
