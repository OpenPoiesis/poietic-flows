//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 14/03/2024.
//

public struct NumericVector: RandomAccessCollection, Equatable {
    public var startIndex: Array<Double>.Index { values.startIndex }
    public var endIndex: Array<Double>.Index { values.endIndex }
    public func index(after index: Index) -> Index { values.index(after: index)}

    public typealias Index = Int
    
    public var values: [Double]

    public init(_ values: [Double]) {
        self.values = values
    }
    
    public init(zeroCount: Int) {
        self.values = Array<Double>(repeating: 0.0, count: zeroCount)
    }
    
    @inlinable
    public subscript(index: Index) -> Double {
        get {
            return values[index]
        }
        set(value) {
            values[index] = value
        }
    }
   
    @inlinable
    public subscript(indices: [Index]) -> NumericVector {
        get {
            var vector = NumericVector(zeroCount: indices.count)
            for (resultIndex, selfIndex) in indices.enumerated() {
                vector[resultIndex] = values[selfIndex]
            }
            return vector
        }
    }

    @inlinable
    public func sum() -> Double {
        return values.reduce(0, +)
    }
    /// Create a new state with variable values multiplied by given value.
    ///
    /// The built-in values will remain the same.
    ///
    @inlinable
    public func multiplied(by value: Double) -> NumericVector {
        return NumericVector(values.map { value * $0 })

    }
    
    @inlinable
    public mutating func multiply(_ factor: Double) {
        for (index, value) in values.enumerated() {
            values[index] = value * factor
        }
    }

    @inlinable
    public static func *=(lhs: inout NumericVector, _ factor: Double) {
        lhs.multiply(factor)
    }

    @inlinable
    public mutating func add(_ other: NumericVector) {
        precondition(other.count == self.values.count)
        for (index, value) in values.enumerated() {
            values[index] = value * other[index]
        }
    }
    @inlinable
    public static func +=(lhs: inout NumericVector, _ other: NumericVector) {
        lhs.add(other)
    }


    @inlinable
    public mutating func subtract(_ other: NumericVector) {
        precondition(other.count == self.values.count)
        for (index, value) in values.enumerated() {
            values[index] = value - other[index]
        }
    }

    @inlinable
    public func negated() -> NumericVector {
        return NumericVector(values.map { $0 * -1 })

    }

    @inlinable
    public static prefix func -(vector: inout NumericVector) -> NumericVector {
        return vector.negated()
    }

    @inlinable
    public static func -=(lhs: inout NumericVector, _ other: NumericVector) {
        lhs.subtract(other)
    }

    /// Create a new state by adding each value with corresponding value
    /// of another state.
    ///
    /// The built-in values will remain the same.
    ///
    /// - Precondition: The states must be of the same length.
    ///
    @inlinable
    public func adding(_ other: NumericVector) -> NumericVector {
        precondition(values.count == other.count,
                     "Vector must be of the same size")
        let result = zip(values, other.values).map {
            (lvalue, rvalue) in lvalue + rvalue
        }
        return NumericVector(result)
    }

    /// Create a new state by subtracting each value with corresponding value
    /// of another state.
    ///
    /// The built-in values will remain the same.
    ///
    /// - Precondition: The states must be of the same length.
    ///
    @inlinable
    public func subtracting(_ other: NumericVector) -> NumericVector {
        precondition(values.count == other.count,
                     "Vector must be of the same size")
        let result = zip(values, other.values).map {
            (lvalue, rvalue) in lvalue - rvalue
        }
        return NumericVector(result)
    }
    
    /// Create a new state with variable values divided by given value.
    ///
    /// The built-in values will remain the same.
    ///
    @inlinable
    public func divided(by value: Double) -> NumericVector {
        return NumericVector(values.map { value / $0 })

    }

    @inlinable
    public static func *(lhs: Double, rhs: NumericVector) -> NumericVector {
        return rhs.multiplied(by: lhs)
    }

    @inlinable
    public static func *(lhs: NumericVector, rhs: Double) -> NumericVector {
        return lhs.multiplied(by: rhs)
    }
    @inlinable
    public static func /(lhs: NumericVector, rhs: Double) -> NumericVector {
        return lhs.divided(by: rhs)
    }
}

extension NumericVector {
    @inlinable
    public static func - (lhs: NumericVector, rhs: NumericVector) -> NumericVector {
        return lhs.subtracting(rhs)
    }
    
    @inlinable
    public static func + (lhs: NumericVector, rhs: NumericVector) -> NumericVector {
        return lhs.adding(rhs)
    }
}
