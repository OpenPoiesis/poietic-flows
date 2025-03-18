//
//  SimulationState.swift
//  
//
//  Created by Stefan Urbanek on 30/07/2022.
//

import PoieticCore

extension SimulationState {
    // Arithmetic operations
    /// Add numeric values to the variables at provided set of indices.
    ///
    /// - Precondition: The caller must assure that the values at given indices
    ///   are convertible to double.
    ///
    public mutating func numericAdd(_ values: NumericVector, atIndices indices: [Index]) {
        for (index, value) in zip (indices, values) {
            let current = self.double(at: index)
            self.values[index] = Variant(current + value)
        }
    }
}



