//
//  World+extensions.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 22/12/2025.
//

@testable import PoieticCore

// Testing convenience methods
extension RuntimeEntity {
    func hasIssue(identifier: String, details: [String:Variant] = [:]) -> Bool {
        guard let issues = self.issues else { return false }
        for issue in issues where issue.identifier == identifier {
            let matches = details.allSatisfy { key, value in
                issue.details[key] == value
            }
            if matches { return true }
        }
        return false
    }
}
