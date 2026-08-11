//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 07/03/2024.
//

import PoieticCore

public struct BoundVariable: TypedVariable, CustomStringConvertible {
    public let index: SimulationState.Index
    public let valueType: ValueType
    
    public var description: String { "BoundVariable(\(index),\(valueType))" }
}
public typealias BoundExpression = ArithmeticExpression<BoundVariable, BuiltinFunction>
