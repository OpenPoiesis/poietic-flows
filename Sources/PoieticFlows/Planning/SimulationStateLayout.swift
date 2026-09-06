//
//  SimulationStateLayout.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 06/09/2026.
//


public extension BuiltinVariable {
    /// Index in the collection of builtin variables.
    ///
    /// - SeeAlso: ``VariableReference/slotIndex``
    var slotIndex: Int {
        switch self {
        case .time: 0
        case .timeDelta: 1
        case .step: 2
        }
    }
    
}

extension VariableReference {
    /// Index in the collection that contains variables of given type.
    public var slotIndex: Int {
        switch self {
        case .builtin(let builtin): builtin.slotIndex
        case .flow(let index):  index
        case .numeric(let index): index
        case .stock(let index): index
        case .variant(let index): index
        }
    }
}

/// State layout is used for storing layout of state variable collections.
///
/// The stored variable references are assured to have validated internal consistency:
/// - sorted by variable storage array type and their index
/// - indices in references are dense (starting with 0 and not skipping a value)
/// - indices and builtins are unique
///
public struct SimulationStateLayout {
    
    public let builtins: [VariableReference]
    public let stocks: [VariableReference]
    public let flows: [VariableReference]
    public let numerics: [VariableReference]
    public let variants: [VariableReference]
    
    /// References in canonical order for simulation output: builtins, stocks, flows, numerics
    /// and variants.
    ///
    public var orderedReferences: [VariableReference] {
        builtins + stocks + flows + numerics + variants
    }
    
    /// Create a new state layout from a list of variable references.
    ///
    /// The variable references must not have duplicates, their index within each type must start at
    /// 0 and must be dense – must not skip an index. Order of items in the `references` parameter
    /// does not matter.
    ///
    ///
    /// - Precondition: The state variables must have unique index within their type and the index,
    ///   when ordered must be equivalent to their order in the list. Examples of invalid reference
    ///   lists:
    ///   `[.stock(0), .stock(0)]` (duplicate index 0)
    ///   or `[.flow(1), .flow(3)]` (missing index 0 and 2).
    ///
    public init(references: [VariableReference]) {
        let builtins = references.filter {$0.type == .builtin }.sorted { $0.slotIndex < $1.slotIndex }
        precondition(builtins.enumerated().allSatisfy { $0.element.slotIndex == $0.offset })
        self.builtins = builtins

        let stocks = references.filter {$0.type == .stock }.sorted { $0.slotIndex < $1.slotIndex }
        precondition(stocks.enumerated().allSatisfy { $0.element.slotIndex == $0.offset })
        self.stocks = stocks

        let flows = references.filter {$0.type == .flow }.sorted { $0.slotIndex < $1.slotIndex }
        precondition(flows.enumerated().allSatisfy { $0.element.slotIndex == $0.offset })
        self.flows = flows

        let numerics = references.filter {$0.type == .numeric }.sorted { $0.slotIndex < $1.slotIndex }
        precondition(numerics.enumerated().allSatisfy { $0.element.slotIndex == $0.offset })
        self.numerics = numerics

        let variants = references.filter {$0.type == .variant }.sorted { $0.slotIndex < $1.slotIndex }
        precondition(variants.enumerated().allSatisfy { $0.element.slotIndex == $0.offset })
        self.variants = variants
    }
}
