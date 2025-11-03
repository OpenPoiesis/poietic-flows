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
    /// Connected named parameters.
    ///
    /// The keys are parameter names, the values are object IDs of the parameter nodes.
    public let connected: [String:ObjectID]
    /// List of parameter names that are not connected.
    public let missing: [String]
    /// List of ``ObjectType/Parameter`` edges that are connected but not used.
    public let unused: [ObjectID]
}


/// Resolve missing and unused parameter connections.
///
/// The Stock and Flow model requires that parameters are connected to the nodes where they are
/// used. The visual representation must match computational representation for human-oriented
/// clarity.
///
class ParameterResolutionSystem {
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ExpressionParserSystem.self), // We need variable names
    ]
    func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        let builtinNames = BuiltinVariable.allNames

        for (id, exprComponent) in frame.filter(ParsedExpressionComponent.self) {
            let requiredParams = exprComponent.variables.subtracting(builtinNames)
            let incomingParams = frame.incoming(id).filter {
                $0.object.type === ObjectType.Parameter
            }

            var connected: [String:ObjectID] = [:]
            var missing: Set<String> = Set(requiredParams)
            var unused: [EdgeObject] = []
            
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
            
            // Store only when there are some issues.
            guard !missing.isEmpty || unused.isEmpty else { continue }
            
            let paramComponent = ResolvedParametersComponent(
                connected: connected,
                missing: Array(missing),
                unused: unused.map { $0.key }
            )
            frame.setComponent(paramComponent, for: id)
        }
    }
}
