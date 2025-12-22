//
//  World+extensions.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 22/12/2025.
//

@testable import PoieticCore

// Testing convenience methods
extension World {
    func objectHasError<T:IssueProtocol>(_ objectID: ObjectID, error: T) -> Bool {
        guard let issues = objectIssues(objectID) else { return false }

        for issue in issues {
            if let objectError = issue.error as? T, objectError == error {
                return true
            }
        }
        return false
    }
}
