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
public struct ResolvedParametersComponent: Component {
    internal init(incoming: [String : ObjectID] = [:],
                  connectedUnnamed: [ObjectID] = [],
                  missing: [String] = [],
                  missingUnnamed: Int = 0,
                  unused: [ObjectID] = []) {
        self.incoming = incoming
        self.connectedUnnamed = connectedUnnamed
        self.missing = missing
        self.missingUnnamed = missingUnnamed
        self.unused = unused
    }
    
    /// Connected named parameters.
    ///
    /// The keys are parameter names, the values are object IDs of the parameter nodes.
    public let incoming: [String:ObjectID]
    /// List of connected parameters where the name is not used, such as parameters
    /// for graphical function, smooth or delay.
    public let connectedUnnamed: [ObjectID]
    /// List of parameter names that are not connected.
    public let missing: [String]
    /// Number of missing unnamed parameters
    public let missingUnnamed: Int
    /// List of ``ObjectType/Parameter`` edges that are connected but not used.
    public let unused: [ObjectID]
}

/// Resolve missing and unused parameter connections.
///
/// The Stock and Flow model requires that parameters are connected to the nodes where they are
/// used. The visual representation must match computational representation for human-oriented
/// clarity.
///
/// - **Input:** Nodes with compiled expression in ``ParsedExpressionComponent`` and objects
/// of auxiliary types: graphical function, smooth or delay.
/// - **Output:** ``ResolvedParametersComponent`` set of each input component
/// - **Forgiveness:** Nothing needed.
/// - **Issues:** Issues added to objects with unknown parameters or unused inputs.
///
public struct ParameterResolutionSystem: System {
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ExpressionParserSystem.self), // We need variable names
    ]

    public init() {}

    public func update(_ world: World) throws (InternalSystemError) {
        guard let frame = world.frame else { return }
        try resolveFormulas(world, frame: frame)
        try resolveAuxiliaries(world, frame: frame, type: .GraphicalFunction)
        try resolveAuxiliaries(world, frame: frame, type: .Delay)
        try resolveAuxiliaries(world, frame: frame, type: .Smooth)
    }

    public func resolveFormulas(_ world: World, frame: DesignFrame) throws (InternalSystemError) {
        let builtinNames = BuiltinVariable.allNames

        for (entityID, exprComponent) in world.query(ParsedExpressionComponent.self) {
            guard let objectID = world.entityToObject(entityID) else { continue }
            let requiredParams = exprComponent.variables.subtracting(builtinNames)
            let incomingParams = frame.incoming(objectID).filter {
                $0.object.type === ObjectType.Parameter
            }

            var connected: [String:ObjectID] = [:]
            var missing: Set<String> = Set(requiredParams)
            var unused: [DesignObjectEdge] = []
            
            for edge in incomingParams {
                let parameter = edge.originObject
                guard let name = parameter.name else { continue }
                if missing.contains(name) {
                    missing.remove(name)
                    connected[name] = edge.target
                }
                else {
                    unused.append(edge)
                }
            }
            // If no parameters are required or unnecessarily connected, just continue
            guard !(connected.isEmpty && missing.isEmpty && unused.isEmpty) else {
                continue
            }

            // Collect issues
            for name in missing {
                let issue = Issue(
                    identifier: "unknown_parameter",
                    severity: .error,
                    system: self,
                    error: ModelError.unknownParameter(name),
                    details: ["name": Variant(name)]
                    )
                world.appendIssue(issue, for: objectID)
            }

            for edge in unused {
                guard let name = edge.originObject.name else { continue }
                let issue = Issue(
                    identifier: "unused_input",
                    severity: .error,
                    system: self,
                    error: ModelError.unusedInput(name),
                    details: ["name": Variant(name)]
                    )
                world.appendIssue(issue, for: objectID)
            }

            let paramComponent = ResolvedParametersComponent(
                incoming: connected,
                missing: Array(missing),
                unused: unused.map { $0.id }
            )
            world.setComponent(paramComponent, for: entityID)
        }
    }
    /// Resolve connections of single-parameter auxiliaries such as graphical function,
    /// delay or smooth.
    ///
    /// - Requirement: The auxiliary should have one incoming parameter.
    ///
    public func resolveAuxiliaries(_ world: World, frame: DesignFrame, type: ObjectType)
    throws (InternalSystemError) {
        for object in frame.filter(type: type) {
            let incomingParams = frame.incoming(object.objectID).filter {
                $0.object.type === ObjectType.Parameter
            }
            let component: ResolvedParametersComponent
            
            if incomingParams.count == 0 {
                let issue = Issue(
                    identifier: "missing_required_parameter",
                    severity: .error,
                    system: self,
                    error: ModelError.missingRequiredParameter,
                )
                world.appendIssue(issue, for: object.objectID)

                component = ResolvedParametersComponent(
                    missingUnnamed: 1
                )
            }
            else if incomingParams.count > 1 {
                let issue = Issue(
                    identifier: "too_many_parameters",
                    severity: .error,
                    system: self,
                    error: ModelError.tooManyParameters,
                )
                world.appendIssue(issue, for: object.objectID)

                component = ResolvedParametersComponent(
                    unused: incomingParams.map { $0.origin }
                )
            }
            else { // if incomingParams.count == 1
                component = ResolvedParametersComponent(
                    connectedUnnamed: [incomingParams[0].origin]
                )
            }

            world.setComponent(component, for: object.objectID)

            
        }
    }
}
