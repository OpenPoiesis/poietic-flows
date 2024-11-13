//
//  BuiltinFunctions.swift
//  
//
//  Created by Stefan Urbanek on 12/07/2022.
//

#if swift(<6)
#error("Not running swift 6!!!")
#endif

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
/// - SeeAlso: ``bindExpression(_:variables:names:functions:)``
///
nonisolated(unsafe) public let BuiltinUnaryOperators: [Function] = [
    .NumericUnary("__neg__") { -$0 }
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
/// - SeeAlso: ``bindExpression(_:variables:names:functions:)``
///
nonisolated(unsafe) public let BuiltinBinaryOperators: [Function] = [
    .NumericBinary("__add__") { $0 + $1 },
    .NumericBinary("__sub__") { $0 - $1 },
    .NumericBinary("__mul__") { $0 * $1 },
    .NumericBinary("__div__") { $0 / $1 },
    .NumericBinary("__mod__") { $0.truncatingRemainder(dividingBy: $1) },
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
nonisolated(unsafe) public let BuiltinFunctions: [Function] = [
    .NumericUnary("abs") {
        $0.magnitude
    },
    .NumericUnary("floor") {
        $0.rounded(.down)
    },
    .NumericUnary("ceiling") {
        $0.rounded(.up)
    },
    .NumericUnary("round") {
        $0.rounded()
    },

    .NumericBinary("power", leftArgument: "value", rightArgument: "exponent") {
        pow($0, $1)
    },

    // Variadic
    
    .NumericVariadic("sum") { args in
        args.reduce(0, { x, y in x + y })
    },
    .NumericVariadic("min") { args in
        args.min()!
    },
    .NumericVariadic("max") { args in
        args.max()!
    },
]

/// List of all built-in functions and operators.
nonisolated(unsafe) let AllBuiltinFunctions: [Function] = BuiltinUnaryOperators
                                    + BuiltinBinaryOperators
                                    + BuiltinFunctions
                                    + PoieticCore.BuiltinFunctions
