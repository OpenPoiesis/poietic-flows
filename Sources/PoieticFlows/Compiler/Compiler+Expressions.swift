//
//  Compiler+Expressions.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 18/04/2025.
//

import PoieticCore

extension Compiler {
    func parseExpressions() throws (InternalCompilerError) {
        parsedExpressions = [:]
        
        for object in orderedObjects {
            guard object.type.hasTrait(.Formula) else {
                continue
            }
            
            guard let formula = try? object["formula"]?.stringValue() else {
                throw .attributeExpectationFailure(object.objectID, "formula")
            }
            
            let parser = ExpressionParser(string: formula)
            let expr: UnboundExpression
            
            do {
                expr = try parser.parse()
            }
            catch {
                issues.append(.expressionSyntaxError(error), for: object.objectID)
                continue
            }
            
            parsedExpressions[object.objectID] = expr
        }
    }
    
    /// Compile a node containing a formula.
    ///
    /// For each node with an arithmetic expression the expression is parsed
    /// from a text into an internal representation. The variable and function
    /// names are resolved to point to actual entities and a new bound
    /// expression is formed.
    ///
    /// - Returns: Computational representation wrapping a formula.
    ///
    /// - Parameters:
    ///     - node: node containing already parsed formula in
    ///       ``ParsedFormulaComponent``.
    ///
    /// - Precondition: The node must have ``ParsedFormulaComponent`` associated
    ///   with it.
    ///
    /// - Throws: ``NodeIssueError`` if there is an issue with parameters,
    ///   function names or other variable names in the expression.
    ///
    func compileFormulaObject(_ object: ObjectSnapshot) throws (InternalCompilerError) -> ComputationalRepresentation {
        guard let unboundExpression = parsedExpressions[object.objectID] else {
            if issues[object.objectID] != nil {
                // Compilation already has issues, we just proceed to collect some more.
                throw .objectIssue
            }
            else {
                throw .formulaCompilationFailure(object.objectID)
            }
        }
        
        // Finally bind the expression.
        //
        let boundExpression: BoundExpression
        do {
            boundExpression = try bindExpression(unboundExpression,
                                                 variables: stateVariables,
                                                 names: nameIndex,
                                                 functions: functions)
        }
        catch /* ExpressionError */ {
            issues.append(.expressionError(error), for: object.objectID)
            throw .objectIssue
        }
        
        return .formula(boundExpression)
    }
}
