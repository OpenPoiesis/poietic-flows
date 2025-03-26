//
//  RegularTimeSeries.swift
//  poietic-core
//
//  Created by Stefan Urbanek on 17/03/2025.
//

import PoieticCore

/// Structure representing numeric time series with regular time intervals.
///
public class RegularTimeSeries /*: Sequence, RandomAccessCollection? */ {
    
    /// Time of the first data sample.
    public let startTime: Double
    /// Time interval between samples.
    public let timeDelta: Double
    var _dataMin: Double? = nil
    var _dataMax: Double? = nil
    
    /// Minimum value in the data series.
    ///
    /// For application convenience, if the data is empty, then the value is zero.
    ///
    public var dataMin: Double {
        if _dataMin == nil {
            _dataMin = data.min() ?? 0
        }
        return _dataMin!
    }

    /// Maximum value in the data series.
    ///
    /// For application convenience, if the data is empty, then the value is zero.
    ///
    public var dataMax: Double {
        if _dataMax == nil {
            _dataMax = data.max() ?? 0
        }
        return _dataMax!
    }
    public var endTime: Double { startTime + Double(data.count - 1) * timeDelta }
    public let data: [Double]
    
    public var isEmpty: Bool { data.isEmpty }

    /// Create new series from data.
    ///
    /// Parameters:
    /// - data: Numeric data of the series.
    /// - startTime: Time of the first data sample.
    /// - timeDelta: Time duration between samples in the data.
    ///
    /// - Note: For application convenience, if the data is empty, then the min/max values
    ///         are zero. It is impractical to have the values to be optional.
    ///
    public init(data: [Double], startTime: Double, timeDelta: Double) {
        precondition(!data.isEmpty, "Time series data is empty")
        self.data = data
        self.startTime = startTime
        self.timeDelta = timeDelta
    }
    
    public func points() -> [Point] {
        var result: [Point] = []
        var time = startTime
        for value in data {
            result.append(Point(time, value))
            time += timeDelta
        }
        return result
    }
}
