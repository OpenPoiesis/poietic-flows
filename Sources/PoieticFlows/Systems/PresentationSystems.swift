//
//  PresentationSystems.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 03/11/2025.
//

import PoieticCore


// TODO: Move to Core/Presentation, with all related structures

/// System that populates chart and chart series entities.
///
/// - **Input:** Nodes of type ``/PoieticCore/ObjectType/Chart`` and ``/PoieticCore/ObjectType/ChartSeries``
/// - **Output:**
///     - Create ``Chart`` component for each chart entity
///     - ``ChartSeries`` for chart series entities, connects to chart with ``ChildOf`` relationship.
/// - **Forgiveness:** Ignore entities where relationships can not be satisfied (missing objects).
///

public struct ChartResolutionSystem: System {
    
    public init(_ world: World) { }

    public func update(_ world: World) throws (InternalSystemError) {
        guard let plane = world.plane else { return }

        processCharts(world, plane: plane)
        processSeries(world, plane: plane)
    }

    func processCharts(_ world: World, plane: DesignPlane) {
        for chartObject in plane.filter(type: .Chart) {
            guard let chartEntity = world.entity(chartObject.objectID)
            else { continue }
            let chartComponent = Chart(from: chartObject)
            chartEntity.setComponent(chartComponent)
        }
    }
    
    func processSeries(_ world: World, plane: DesignPlane) {

        for seriesEdge in plane.filter(type: .ChartSeries) {
            guard let seriesEntity = world.entity(seriesEdge.objectID),
                  case .edge(let originID, let targetID) = seriesEdge.topology,
                  let targetObject = plane[targetID],
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
            seriesEntity.relate(ChildOf(), to: chartEntity.runtimeID)
        }
    }
}
