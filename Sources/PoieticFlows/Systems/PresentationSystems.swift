//
//  PresentationSystems.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore

/// System that collects all charts.
///
/// - **Input:** Nodes of type ``/PoieticCore/ObjectType/Chart``,
/// - **Output:** Set ``ChartComponent`` for each chart node.
/// - **Forgiveness:** Nothing to be forgiven.
///
@available(*, deprecated, message: "boo!")
public struct ChartResolutionSystem: System {
    
    public init(_ world: World) { }

    public func update(_ world: World) throws (InternalSystemError) {
        guard let frame = world.frame else { return }
        let chartObjects = frame.filter { $0.type === ObjectType.Chart }

        for chartObject in chartObjects {
            guard let entity = world.entity(chartObject.objectID) else { continue }
            let seriesEdges = frame.outgoing(chartObject.objectID).filter {
                $0.object.type === ObjectType.ChartSeries
            }
            
            let series = seriesEdges.map { $0.targetObject }
            let chart = ChartComponent(chartObject: chartObject, series: series)
            entity.setComponent(chart)
        }
    }
}


// TODO: Move to Core/Presentation, with all related structures

/// System that populates chart and chart series entities.
///
/// - **Input:** Nodes of type ``/PoieticCore/ObjectType/Chart`` and ``/PoieticCore/ObjectType/ChartSeries``
/// - **Output:**
///     - Create ``Chart`` component for each chart entity
///     - ``ChartSeries`` for chart series entities, connects to chart with ``ChildOf`` relationship.
/// - **Forgiveness:** Ignore entities where relationships can not be satisfied (missing objects).
///

public struct NewChartResolutionSystem: System {
    
    public init(_ world: World) { }

    public func update(_ world: World) throws (InternalSystemError) {
        guard let frame = world.frame else { return }

        processCharts(world, frame: frame)
        processSeries(world, frame: frame)
    }

    func processCharts(_ world: World, frame: DesignFrame) {
        for chartObject in frame.filter(type: .Chart) {
            guard let chartEntity = world.entity(chartObject.objectID)
            else { continue }
            let chartComponent = Chart(from: chartObject)
            chartEntity.setComponent(chartComponent)
        }
    }
    
    func processSeries(_ world: World, frame: DesignFrame) {

        for seriesEdge in frame.filter(type: .ChartSeries) {
            guard let seriesEntity = world.entity(seriesEdge.objectID),
                  case .edge(let originID, let targetID) = seriesEdge.structure,
                  let targetObject = frame[targetID],
                  let targetEntity = world.entity(targetID),
                  let chartEntity = world.entity(originID)
            else { continue }

            // FIXME: Use bounds from series object first.
            let bounds = DisplayValueBounds(from: targetObject)
            let color: String? = targetObject["color"]
            let colorKey: AdaptableColorKey?
            colorKey = color.map { AdaptableColorKey(rawValue: $0) } ?? nil

            let series = ChartSeries(
                target: targetEntity.runtimeID,
                colorKey: colorKey,
                displayBounds: bounds
            )
            seriesEntity.setComponent(series)
            seriesEntity.setComponent(ChildOf(chartEntity.runtimeID))
        }
    }
}
