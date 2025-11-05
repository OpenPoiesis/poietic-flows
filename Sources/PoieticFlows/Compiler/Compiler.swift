//
//  Compiler.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 21/06/2022.

// TODO: Add compileExpressions() -> [ObjectID:UnboundExpression], make it independent
// TODO: Add resolvedParameters(...) -> something, make it independent (for auto-connect)
// TODO: Remove checks that are not necessary with ValidatedFrame (safely make them preconditions/fatalErrors)

import PoieticCore


public struct CompilationIssueCollection: Sendable {
    /// Issues specific to particular object.
    public var objectIssues: [ObjectID:[ObjectIssue]]
    
    /// Create an empty design issue collection.
    public init() {
        self.objectIssues = [:]
    }
    
    public var isEmpty: Bool {
        objectIssues.isEmpty
    }
    
    public subscript(id: ObjectID) -> [ObjectIssue]? {
        return objectIssues[id]
    }
    
    /// Append an issue for a specific object.
    public mutating func append(_ issue: ObjectIssue, for id: ObjectID) {
        objectIssues[id, default: []].append(issue)
    }

    public func asDesignIssueCollection() -> DesignIssueCollection {
        var result: DesignIssueCollection = DesignIssueCollection()

        for (id, errors) in objectIssues {
            for error in errors {
                result.append(error.asDesignIssue(), for: id)
            }
        }
        return result
    }
}
/// Error thrown by the compiler during compilation.
///
/// The only relevant case is ``hasIssues``, any other case means a programming error.
///
/// After catching the ``hasIssues`` error, the caller might get the issues from
/// the compiler and propagate them to the user.
///
public enum CompilerError: Error {
    case issues([ObjectID:[Issue]])
    
    /// Error caused by some internal functioning. This error typically means something was not
    /// correctly validated either within the library or by an application. The internal error
    /// is not caused by the user.
    case internalError(InternalCompilerError)
    
}



/// Error caused by some compiler internals, not by the user.
///
/// This error should not be displayed to the user fully, only as a debug information or as an
/// information provided to the developers by the user.
///
public enum InternalCompilerError: Error, Equatable {
    /// Error thrown during compilation that should be captured by the compiler.
    ///
    /// Used to indicate that the compilation might continue to collect more errors, but must
    /// result in an error at the end.
    ///
    /// This error should never escape the compiler.
    ///
    case objectIssue
    
    /// Attribute is missing or attribute type is mismatched. This error means
    /// that the frame is not valid according to the ``FlowsMetamodel``.
    case attributeExpectationFailure(ObjectID, String)
    
    /// Formula compilation failed in an unexpected way.
    case formulaCompilationFailure(ObjectID)
    
    // Invalid Frame Error - validation on the caller side failed
    case structureTypeMismatch(ObjectID)
    case objectNotFound(ObjectID)
}




/// Legacy wrapper to provide same API. DO NOT USE!
///
/// An object that compiles the model into an internal representation called Compiled Model.
///
/// The design represents an idea or a creation of a user in a form that
/// is closest to the user. To perform a simulation we need a different form
/// that can be interpreted by a machine.
///
/// The purpose of the compiler is to validate the design and
/// translate it into an internal representation.
///
/// - SeeAlso: ``compile()``, ``SimulationPlan``
///
@available(*, deprecated, message: "Moving towards Systems")
public class Compiler {
    public let frame: RuntimeFrame

    @available(*, deprecated, message: "Moving towards Systems")
    public init(frame: ValidatedFrame) {
        self.frame = RuntimeFrame(frame)
    }

    @available(*, deprecated, message: "Moving towards Systems")
    public func compile() throws (CompilerError) -> SimulationPlan {
        let scheduler = SystemScheduler()
        scheduler.register([
            ExpressionParserSystem(),
            ParameterResolutionSystem(),
            ComputationOrderSystem(),
            NameResolutionSystem(),
            FlowCollectorSystem(),
            StockDependencySystem(),
            SimulationCompilerSystem(),
        ]
        )
        
        do {
            try scheduler.execute(frame)
        }
        catch {
            fatalError("Execution failed: \(error)")
        }
        
        if frame.hasIssues {
            throw .issues(frame.issues)
        }
        guard let plan = frame.frameComponent(SimulationPlan.self) else {
            fatalError("Plan was not created")
        }
        return plan
    }
}

