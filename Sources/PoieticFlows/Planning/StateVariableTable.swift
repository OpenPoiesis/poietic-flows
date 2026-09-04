//
//  StateVariableTable.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 20/08/2026.
//

import PoieticCore

struct AllocationSequence {
    private(set) var nextValue: Int = 0
    
    mutating func next() -> Int {
        let value = nextValue
        nextValue += 1
        return value
    }
}

/// Allocation table for state variables.
///
/// Planner uses this table to allocate simulation state variables.
///
/// - Allocates variable, assigns a reference to the state and assigns column in the simulation
///   result
/// - Maintains index of bound variables by name for expression binding
/// - Maintains index of bound variables by object ID for parameter resolution (delay, smooth,
///   graphical function inputs)
///
/// Invariants:
/// - Only object and builtin names are stored in the name index.
/// - Only object primary variables are stored in the object index (no builtins, no internal or
///   estimated value variables)
class StateVariableTable {
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
    private var nameIndex: [String: BoundVariable] = [:]
    
    /// Index to primary represented value of an object.
    ///
    /// Used to resolve parameters of delay/smooth/graphical function nodes.
    private var objectIndex: [ObjectID: BoundVariable] = [:]

    // State allocation counts
    var numericVariableCount: Int { numericSequence.nextValue }
    var variantVariableCount: Int { variantSequence.nextValue }

    // MARK: - Lookup
    
    func boundVariable(_ objectID: ObjectID) -> BoundVariable? {
        return objectIndex[objectID]
    }

    func reference(_ objectID: ObjectID) -> SimulationState.Reference? {
        return objectIndex[objectID]?.reference
    }

    // MARK: - Allocation
    
    /// Allocate and register a builtin.
    ///
    /// Builtins consume no vector space. They are bindable by name and receive a state variable
    /// for reporting
    func allocate(builtin: BuiltinVariable) {
        let name = builtin.normalizedKey

        precondition(nameIndex[name] == nil)

        let ref: SimulationState.Reference = .builtin(builtin)
        
        nameIndex[name] = BoundVariable(reference: ref, valueType: builtin.valueType)
        register(name, reference: ref, content: .builtin(builtin))
    }
    
    /// Allocate a primary variable of a simulation object
    ///
    /// Registers object name (for binding) and the object ID (for parameter resolution).
    /// Resulted variable content type is `.object`
    ///
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


    /// Internal numeric state variable slot.
    ///
    /// Internal variables are non-bindable by name.
    func allocateInternalNumeric(name: String, for objectID: ObjectID) -> Int
    {
        let index = numericSequence.next()
        register(name, reference: .numeric(index), content: .internalState(objectID))
        return index
    }
    
    /// Internal variant state variable slot.
    ///
    /// Internal variables are non-bindable by name.
    func allocateInternalVariant(name: String, for objectID: ObjectID) -> Int
    {
        let index = variantSequence.next()
        register(name, reference: .variant(index), content: .internalState(objectID))
        return index
    }

    /// Estimated value variable slot of a flow.
    ///
    /// Reference is stored in ``BoundFlow/estimatedNumericIndex``.
    func allocateEstimatedNumeric(_ name: String, for objectID: ObjectID) -> Int
    {
        let index = numericSequence.next()
        register(name, reference: .numeric(index), content: .estimated(objectID))
        return index
    }

    // MARK: - Registration
    
    /// Creates a state variable, assigns it a result column and appends it to the list of state
    /// variables.
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
