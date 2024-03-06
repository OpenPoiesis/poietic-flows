//
//  BuiltinFunctions.swift
//  
//
//  Created by Stefan Urbanek on 12/07/2022.
//

import PoieticCore

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// Mark: Builtins

/// List of built-in numeric unary operators.
///
/// The operators:
///
/// - `__neg__` is `-` unary minus
///
/// - SeeAlso: ``bindExpression(_:variables:functions:)``
///
public let BuiltinUnaryOperators: [Function] = [
    .numericUnary("__neg__") { -$0 }
]

/// List of built-in numeric binary operators.
///
/// The operators:
///
/// - `__add__` is `+` addition
/// - `__sub__` is `-` subtraction
/// - `__mul__` is `*` multiplication
/// - `__div__` is `/` division
/// - `__mod__` is `%` remainder
///
/// - SeeAlso: ``bindExpression(_:variables:functions:)``
///
public let BuiltinBinaryOperators: [Function] = [
    .numericBinary("__add__") { $0 + $1 },
    .numericBinary("__sub__") { $0 - $1 },
    .numericBinary("__mul__") { $0 * $1 },
    .numericBinary("__div__") { $0 / $1 },
    .numericBinary("__mod__") { $0.truncatingRemainder(dividingBy: $1) },
]

/// List of built-in numeric function.
///
/// The functions:
///
/// - `abs(number)` absolute value
/// - `floor(number)` rounded down, floor value
/// - `ceiling(number)` rounded up, ceiling value
/// - `round(number)` rounded value
/// - `sum(number, ...)` sum of multiple values
/// - `min(number, ...)` min out of of multiple values
/// - `max(number, ...)` max out of of multiple values
///
public let BuiltinFunctions: [Function] = [
    .numericUnary("abs") {
        $0.magnitude
    },
    .numericUnary("floor") {
        $0.rounded(.down)
    },
    .numericUnary("ceiling") {
        $0.rounded(.up)
    },
    .numericUnary("round") {
        $0.rounded()
    },

    .numericBinary("power", leftArgument: "value", rightArgument: "exponent") {
        pow($0, $1)
    },

    // Variadic
    
    .numericVariadic("sum") { args in
        args.reduce(0, { x, y in x + y })
    },
    .numericVariadic("min") { args in
        args.min()!
    },
    .numericVariadic("max") { args in
        args.max()!
    },
]

/// List of all built-in functions and operators.
let AllBuiltinFunctions: [Function] = BuiltinUnaryOperators
                                    + BuiltinBinaryOperators
                                    + BuiltinFunctions


// MARK: - Experimental -

/// List of built-in binary comparison operators.
///
/// The operators:
///
/// - `__eq__` is `==`
/// - `__neq__` is `!=`
/// - `__gt__` is `>`
/// - `__ge__` is `>=`
/// - `__lt__` is `<`
/// - `__le__` is `<=>`
///
/// - SeeAlso: ``bindExpression(_:variables:functions:)``
///
public let BuiltinComparisonOperators: [Function] = [
    .comparison("__eq__") { (lhs, rhs) in
        return lhs == rhs
    },
    .comparison("__neq__") { (lhs, rhs) in
        return lhs != rhs
    },
    .comparison("__lt__") { (lhs, rhs) in
        return try lhs.precedes(rhs)
    },
]

