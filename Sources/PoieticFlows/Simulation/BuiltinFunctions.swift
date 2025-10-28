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

extension Function {
    /// Numeric negation function.
    ///
    /// Used for the unary `-` minus operator.
    ///
    nonisolated(unsafe)
    public static let NumericNegation = Function(numericUnary: "__neg__") { -$0 }
    nonisolated(unsafe)
    public static let NumericUnaryOperators = [
        NumericNegation
    ]
    
    // Binary
    nonisolated(unsafe)
    public static let NumericAdd = Function(numericBinary: "__add__") { $0 + $1 }
    nonisolated(unsafe)
    public static let NumericSubtract = Function(numericBinary: "__sub__") { $0 - $1 }
    nonisolated(unsafe)
    public static let NumericMultiply = Function(numericBinary: "__mul__") { $0 * $1 }
    nonisolated(unsafe)
    public static let NumericDivide = Function(numericBinary: "__div__") { $0 / $1 }
    nonisolated(unsafe)
    public static let NumericModulo = Function(numericBinary: "__mod__") {
        $0.truncatingRemainder(dividingBy: $1)
    }
    nonisolated(unsafe)
    public static let NumericPower = Function(numericBinary: "__pow__") {
        pow($0, $1)
    }

    nonisolated(unsafe) static let NumericBinaryOperators = [
        NumericAdd,
        NumericSubtract,
        NumericMultiply,
        NumericDivide,
        NumericModulo,
        NumericPower,
    ]

    /// Function for computing absolute (numeric) value.
    ///
    /// Expression: `abs(number)`
    ///
    nonisolated(unsafe)
    public static let Abs = Function(numericUnary: "abs") {
        $0.magnitude
    }
    /// Function for computing rounded down, floor value.
    ///
    /// Expression: `floor(number)`
    ///
    nonisolated(unsafe)
    public static let Floor = Function(numericUnary: "floor") {
        $0.rounded(.down)
    }
    /// Function for computing rounded up, ceiling value.
    ///
    /// Expression: `ceiling(number)`
    ///
    nonisolated(unsafe)
    public static let Ceiling = Function(numericUnary: "ceiling") {
        $0.rounded(.up)
    }
    /// Function for computing rounded numeric value.
    ///
    /// Expression: `round(number)`
    ///
    nonisolated(unsafe)
    public static let Round = Function(numericUnary: "round") {
        $0.rounded()
    }

    /// Function for computing power.
    ///
    /// Expression: `power(value, exponent)`
    ///
    nonisolated(unsafe)
    public static let Power = Function(
        numericBinary: "power",
        leftName: "value",
        rightName: "exponent")
    {
        pow($0, $1)
    }

    nonisolated(unsafe)
    public static let Exp = Function(numericUnary: "exp") {
        exp($0)
    }

    /// Function for computing a sum of one or more values.
    ///
    /// Expression: `sum(number, ...)`
    nonisolated(unsafe)
    public static let Sum = Function(numericVariadic: "sum") {
        $0.reduce(0, { x, y in x + y })
    }

    /// Function for finding a minimum of one or more values.
    ///
    /// Use: `min(number, ...)` min out of of multiple values
    nonisolated(unsafe)
    public static let Min = Function(numericVariadic: "min") {
        $0.min()!
    }

    /// Function for finding a maximum of one or more values.
    ///
    /// Use: `max(number, ...)` max out of of multiple values
    nonisolated(unsafe)
    public static let Max = Function(numericVariadic: "max") {
        $0.max()!
    }
    
    nonisolated(unsafe)
    public static let BasicNumericFunctions = [
        Abs,
        Floor,
        Ceiling,
        Round,
        Power,
        Exp,
        Sum,
        Min,
        Max,
    ]
    
    nonisolated(unsafe)
    public static let AllBuiltinFunctions =
        NumericUnaryOperators
        + NumericBinaryOperators
        + BasicNumericFunctions
        + ComparisonOperators
        + BooleanFunctions
}
