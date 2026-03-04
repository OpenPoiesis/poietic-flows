//
//  NumericValueComponents.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 04/03/2026.
//

import PoieticCore

/// Bounds used for value visualisation, for example in charts or value indicators.
///
/// Component is derived from ``/PoieticCore/Trait/NumericIndicator``
/// by ``DisplayMetadataProcessingSystem``.
///
public struct DisplayValueBounds: Component {
    /// Minimal value to be displayed.
    ///
    /// If `nil`, then it is assumed to be auto-scaled from the simulation result, or default 0
    public let min: Double?

    /// Maximum value to be displayed.
    /// If `nil`, then it is assumed to be auto-scaled from the simulation result, or default 0
    public let max: Double?

    /// If `nil`, then it is assumed to be same as ``min``.
    public let baseline: Double?
    
    /// - Precondition: If both `min` and `max` are not-nil, then `min` must be less or equal `max`.
    public init(min: Double?, max: Double?, baseline: Double?) {
        self.min = min
        self.max = max
        if let min, let max {
            precondition(min <= max)
        }
        self.baseline = baseline ?? min
    }
}


/// Defines bounds of possible values for a metric, including baseline.
/// Used for visual indicators, chart axes, and value normalisation.
public struct ValueBounds {
    // TODO: Consider name NumericValueDomain
    /// The minimum allowable value (underflow occurs below this)
    public let min: Double
    
    /// The maximum allowable value (overflow occurs above this)
    public let max: Double
    
    /// The reference point separating negative from positive values
    /// Defaults to midpoint between min and max if not explicitly set
    public let baseline: Double
    
    /// Range of the bounds: `max - min`.
    public var range: Double { max - min }
    
    /// Convenience computed variable for normalising baseline.
    ///
    /// Same as:
    ///
    /// ```swift
    /// let bounds: ValueBounds // Given
    /// let baselineScale = bounds.normalized(bounds.baseline)
    /// ```
    public var normalizedBaseline: Double { normalized(baseline) }

    /// Creates value bounds with specified min, max and baseline
    /// - Parameters:
    ///   - min: Lower bound
    ///   - max: Upper bound
    ///   - baseline: Reference point (defaults to midpoint if nil)
    ///   - limit: Limit the bounds to specific values, if provided.
    /// - Precondition: ``max`` must be greater or equal than ``min``.
    public init(min: Double, max: Double, baseline: Double, limit: DisplayValueBounds? = nil) {
        precondition(max >= min)
        if let limit {
            self.min = limit.min ?? min
            self.max = limit.max ?? max
            self.baseline = limit.baseline ?? baseline
        }
        else {
            self.min = min
            self.max = max
            self.baseline = baseline
        }
    }
    
    /// The status of a value within this bounds domain
    public enum State {
        /// Value > max
        case overflow
        /// Value < min
        case underflow
        /// Value ≥ baseline and ≤ max
        case positive
        /// Value < baseline and ≥ min
        case negative
        
        var isWithinBounds: Bool {
            switch self {
            case .overflow, .underflow: false
            case .positive, .negative: true
            }
        }
    }
    
    /// Determines the status of a given value within this domain
    /// - Parameter value: The value to check
    /// - Returns: The ``Status`` indicating where the value lies
    public func state(of value: Double) -> State {
        if value > max { .overflow }
        else if value < min { .underflow }
        else if value >= baseline { .positive }
        else { .negative }
    }
    
    /// Clamps a value to the domain bounds if necessary
    /// - Parameter value: The value to clamp
    /// - Returns: The value clamped to a range [min, max]
    public func clamp(_ value: Double) -> Double {
        return Swift.max(self.min, Swift.min(self.max, value))
    }
    
    /// Normalizes a value to the 0-1 range based on domain bounds
    /// - Parameter value: The value to normalize
    /// - Returns: Normalized value between 0 and 1, with bounds clipping
    public func normalized(_ value: Double) -> Double {
        let clipped = self.clamp(value)
        return (clipped - min) / (max - min)
    }
    
//    /// Returns the relative position of a value along the domain,
//    /// with baseline mapping to 0.5 for symmetrical display
//    func relativePosition(_ value: Double) -> Double {
//        let clipped = clip(value)
//
//        // For values below baseline, map to [0, 0.5]
//        if clipped <= baseline {
//            return 0.5 * (clipped - min) / (baseline - min)
//        }
//        // For values above baseline, map to [0.5, 1]
//        else {
//            return 0.5 + 0.5 * (clipped - baseline) / (max - baseline)
//        }
//    }
}

