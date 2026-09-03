//
//  StateVariableTable.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 20/08/2026.
//

import PoieticCore

struct AllocationSequence {
    var nextValue: Int = 0
    
    mutating func next() -> Int {
        let value = nextValue
        nextValue += 1
        return value
    }
}

/// Allocation table for state variables.
///
class StateVariableTable {
    // TODO: Rename to StatePlanningTable/StatePlanningContext?
    
    public private(set) var variables: [StateVariable] = []

    private var resultColumnSequence = AllocationSequence()
    private var stockSequence = AllocationSequence()
    private var flowSequence = AllocationSequence()
    private var numericSequence = AllocationSequence()
    private var variantSequence = AllocationSequence()
    
    /// Name to variable map used for arithmetic expression binding.
    ///
    /// Contains only variables that can be referenced by the arithmetic expression –
    /// objects and built-in variables.
    ///
    /// - SeeAlso: ``variable(named:)``
    private var nameIndex: [String: BoundVariable] = [:]
    
    /// Index to primary represented value of an object.
    private var objectIndex: [ObjectID: BoundVariable] = [:]

    var numericVariableCount: Int { numericSequence.nextValue }
    var variantVariableCount: Int { variantSequence.nextValue }

    
    func boundVariable(_ objectID: ObjectID) -> BoundVariable? {
        return objectIndex[objectID]
    }

    func reference(_ objectID: ObjectID) -> SimulationState.Reference? {
        return objectIndex[objectID]?.reference
    }
    func valueType(of objectID: ObjectID) -> ValueType? {
        return objectIndex[objectID]?.valueType
    }

    // Builtins consume no vector space — just a registered reference.
    func allocate(builtin: BuiltinVariable) {
        let name = builtin.normalizedKey

        precondition(nameIndex[name] == nil)

        let ref: SimulationState.Reference = .builtin(builtin)
        
        nameIndex[name] = BoundVariable(reference: ref, valueType: builtin.valueType)
        register(name, reference: ref, content: .builtin(builtin))
    }
    
    func allocate(objectID: ObjectID,
                  name: String,
                  role: SimulationRole,
                  valueType: ValueType) -> StateVariable
    {
        precondition(nameIndex[name] == nil)
        precondition(objectIndex[objectID] == nil)

        let ref: SimulationState.Reference
        
        switch role {
        case .stock:
            ref = .stock(stockSequence.next())
        case .flow:
            ref = .flow(flowSequence.next())
        case .auxiliary:
            switch valueType {
            case .atom(.double), .atom(.int):
                ref = .numeric(numericSequence.next())
            default:
                ref = .variant(variantSequence.next())
            }
        }

        let bound = BoundVariable(reference: ref, valueType: valueType)
        nameIndex[name] = bound
        objectIndex[objectID] =  bound
        
        return register(name, reference: ref, content: .object(objectID))
    }


    func allocateInternalNumeric(name: String, for objectID: ObjectID) -> Int
    {
        let index = numericSequence.next()
        register(name, reference: .numeric(index), content: .internalState(objectID))
        return index
    }
    
    func allocateInternalVariant(name: String, for objectID: ObjectID) -> Int
    {
        let index = variantSequence.next()
        register(name, reference: .variant(index), content: .internalState(objectID))
        return index
    }

    func allocateEstimatedNumeric(_ name: String, for objectID: ObjectID) -> Int
    {
        let index = numericSequence.next()
        register(name, reference: .numeric(index), content: .estimated(objectID))
        return index
    }

    @discardableResult
    func register(_ name: String, reference: SimulationState.Reference, content: StateVariable.Content) -> StateVariable {
        let variable = StateVariable(
            reference: reference,
            resultColumn: resultColumnSequence.next(),
            name: name,
            content: content
        )
        self.variables.append(variable)
        
        return variable
    }
}

extension StateVariableTable: VariableNameLookup {
    typealias Variable = BoundVariable
    func variable(named name: String) -> Variable? {
        let normalizedKey = NormalizedName.normalize(name)
        return nameIndex[normalizedKey]
    }
}
