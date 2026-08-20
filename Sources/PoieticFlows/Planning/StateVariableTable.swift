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
    var variables: [StateVariable] = []

    /// Object ID to variable index
    var objectIndex: [ObjectID:Int] = [:]
    /// Object name to variable index
    var nameIndex: [String:Int] = [:]
    
    func allocate(builtin: BuiltinVariable) -> Int
    {
        let index = self.allocate(content: .builtin(builtin),
                                  valueType: builtin.valueType,
                                  name: builtin.name)
        return index
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
    @discardableResult
    func allocate(content: StateVariable.Content, valueType: ValueType, name: String) -> Int
    {
        let index = variables.count
        let variable = StateVariable(index: index, content: content, valueType: valueType, name: name)
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
   
    func valueType(at index: Int) -> ValueType? {
        return variables[index].valueType
    }
    
    func index(_ objectID: ObjectID) -> Int? {
        return objectIndex[objectID]
    }
}

extension StateVariableTable: VariableNameLookup {
    typealias Variable = BoundVariable
    func variable(named name: String) -> Variable? {
        guard let index = nameIndex[name]
        else { return nil }
        let variable = variables[index]
        return BoundVariable(index: index, valueType: variable.valueType)
    }

}
