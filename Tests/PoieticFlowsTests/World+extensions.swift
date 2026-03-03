//
//  World+extensions.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 22/12/2025.
//

@testable import PoieticCore

// Testing convenience methods
extension RuntimeEntity {
    func hasIssue(identifier: String) -> Bool {
        guard let issues = self.issues else { return false }
        return issues.contains { $0.identifier == identifier }
    }


    func hasError<T:IssueProtocol>(_ error: T) -> Bool {
        guard let issues = self.issues else { return false }

        for issue in issues {
            if let objectError = issue.error as? T, objectError == error {
                return true
            }
        }
        return false
    }
}
