//
//  StateVariableTable.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 20/08/2026.
//

import PoieticCore

/// Allocation table for state variables.
///
class StateVariableTable {
    public private(set) var variables: [StateVariable] = []

    private var nextStock = 0
    private var nextFlow = 0
    private var nextNumeric = 0
    private var nextVariant = 0
    
    /// Name to variable map used for arithmetic expression binding.
    ///
    /// Contains only variables that can be referenced by the arithmetic expression –
    /// objects and built-in variables.
    ///
    /// - SeeAlso: ``variable(named:)``
    private var nameIndex: [String: BoundVariable] = [:]
    
    /// Index to primary represented value of an object.
    private var objectIndex: [ObjectID: SimulationState.Reference] = [:]

    
    func reference(_ objectID: ObjectID) -> SimulationState.Reference? {
        return objectIndex[objectID]
    }
    
    // Builtins consume no vector space — just a registered reference.
    func allocate(builtin: BuiltinVariable) {
        let variable = BoundVariable(reference: .builtin(builtin),
                                     valueType: builtin.valueType)
        register(name: builtin.name, variable: variable)
    }
    
    func allocate(object: ObjectID,
                  role: SimulationRole,
                  name: String,
                  valueType: ValueType)
    {
        let ref: SimulationState.Reference
        
        switch role {
        case .stock:
            let index = allocate(stock: name)
            ref = .stock(index)
        case .flow: break
            let index = allocate(flow: name)
            ref = .stock(index)
        case .auxiliary: break
            switch valueType {
            case .atom(.double), .atom(.int):
                let index = allocate(numeric: name)
            }
        }
    }

    func allocate(stock name: String) -> Int {
        let ref = register(.stock(nextStock), name: name)
        nextStock += 1
        return ref
    }

    func allocate(flow name: String) -> Int {
        let ref = register(.flow(nextFlow), name: name)
        nextFlow += 1
        return ref
    }

    func allocate(numeric content: StateVariable.Content, name: String, isInternal: Bool) -> SimulationState.Reference {
        let ref = register(.numeric(nextNumeric), name: name)
        nextNumeric += 1
        return ref
    }

    func allocate(variant name: String) -> SimulationState.Reference {
        let ref = register(.variant(nextVariant), name: name)
        nextVariant += 1
        return ref
    }

    private func register(_ ref: SimulationState.Reference, name: String) -> SimulationState.Reference {
        // append NEWStateVariable, fill nameIndex/objectIndex, return ref
    }

    /// Allocate a state variable with given specification and return its index in the
    /// simulation state vector.
    ///
    /// Internal state variables are not registered in the table, they can be referenced only
    /// by index. Their internal name is in form `prefix + '_' + object ID`, for example
    /// `flow_adjusted_12` or `delay_init_3`.
    ///
    /// - Precondition: If the variable type is object or builtin, then the name must not already
    ///   exist in the table. In addition to that, there can be only one object variable with given
    ///   ID.
#if false
    @discardableResult
    func OLD_allocate(content: StateVariable.Content, valueType: ValueType, name: String) -> Int
    {
        let index = variables.count
        let variable = StateVariable(index: index,
                                     content: content,
                                     valueType: valueType,
                                     nameKey: name)
        variables.append(variable)
       
        switch content {
        case .object(let id):
            precondition(objectIndex[id] == nil)
            precondition(nameIndex[name] == nil)
            objectIndex[id] = index
            nameIndex[name] = index
        case .builtin(_):
            precondition(nameIndex[name] == nil)
            nameIndex[name] = index
        case .adjustedResult(_): break
        case .internalState(_): break
        }
        
        return index
    }
#endif
}

extension StateVariableTable: VariableNameLookup {
    typealias Variable = BoundVariable
    func variable(named name: String) -> Variable? {
        let normalizedKey = NormalizedName.normalize(name)
        return nameIndex[normalizedKey]
    }
}
