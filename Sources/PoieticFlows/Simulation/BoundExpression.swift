//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 07/03/2024.
//

import PoieticCore

public struct BoundVariable: TypedVariable {
    public let reference: VariableReference
    public let valueType: ValueType
    
    public var description: String { "BoundVariable(\(reference), \(valueType))" }
}

public typealias BoundExpression = ArithmeticExpression<BoundVariable, BuiltinFunction>
