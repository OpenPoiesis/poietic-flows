//
//  SimulationPlanner.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 20/08/2026.
//

import PoieticCore

/// Error thrown during the simulation planning process
public enum PlanningError: Error, Equatable {
    /// Issue with object has been detected, appended to the list of issues. The caller might
    /// continue with the operation to gather more issues. Criticality of this error is
    /// problem specific.
    case userIssue
    
    case corruptedVariableTable
    
    /// Design object does not have content as required. This indicated that the design was
    /// not properly validated against ``StockFlowMetamodel``.
    ///
    case invalidObject(ObjectID, String)
    /// Missing required component. Probably the dependency was not satisfied.
    case missingComponent(ObjectID, String)
    case corruptedComponent(ObjectID, String)
    case unprocessedObjects
}


/// Object that plans a computation.
///
public class SimulationPlanner {
    public static let IssueSourceName: String = "SimulationPlanner"
    var variables: StateVariableTable
    var hasError: Bool
    
    public init() {
        variables = StateVariableTable()
        hasError = false
    }
    
    /// Create a simulation plan for specified objects.
    ///
    /// - Parameters:
    ///     - simulationOrder: Simulation objects ordered by their computational dependencies.
    ///       Created by the ``ComputationOrderSystem``.
    ///     - world: World for which the plan is being created.
    ///
    /// Requirements for the world:
    ///
    /// - Must contain entities for every design object in the `order`
    /// - Entities must have components that correspond to their type, as produced by the analytical
    ///   systems before planning.
    ///
    /// Side-effect: The function attaches `HasNumericIndicator` component on entities with
    /// numeric value.
    ///
    /// - Important: The objects are expected to be ordered by their computational dependency. If they are not
    ///   ordered, the simulation result is undefined.
    ///
    /// - Throws: ``PlanningError``. Any other value except ``PlanningError/userIssue`` means
    ///   a programming error.
    ///
    public func createPlan(order simulationOrder: SimulationOrder, in world: World)
    throws (PlanningError) -> SimulationPlan
    {
        var flows: [SimulationObject] = []
        var stocks: [SimulationObject] = []

        let builtins = prepareBuiltins()

        let simulationObjects = try compileObjects(objects: simulationOrder.objects, in: world)
        
        // If we have errors, finish early without creating the final plan.
        guard !hasError else { throw .userIssue }

        for object in simulationObjects {
            switch object.role {
            case .flow: flows.append(object)
            case .stock: stocks.append(object)
            case .auxiliary: break
            }
        }
        
        /// Verify that all objects are processed
        guard simulationOrder.objects.count == simulationObjects.count else {
            throw .unprocessedObjects
        }

        let boundFlows = try bindFlows(flows, world: world)

        var flowIndices: [ObjectID:Int] = [:]
        for (index, flow) in boundFlows.enumerated() {
            flowIndices[flow.objectID] = index
        }
        
        let boundStocks = try bindStocks(stocks, flowIndices: flowIndices, world: world)
        
        let plan = SimulationPlan(
            simulationObjects: simulationObjects,
            stateVariables: variables.variables,
            builtins: builtins,
            stocks: boundStocks,
            flows: boundFlows
        )
        
        return plan
    }

    func prepareBuiltins() -> BoundBuiltins {
        let builtins = BoundBuiltins(
            step: variables.allocate(builtin: .step),
            time: variables.allocate(builtin: .time),
            timeDelta: variables.allocate(builtin: .timeDelta)
        )
        
        return builtins
    }
    

    // MARK: - Binding of stocks and flows
    func bindFlows(_ flows: [SimulationObject], world: World)
    throws (PlanningError) -> [BoundFlow]
    {
        var boundFlows: [BoundFlow] = []
        
        for flow in flows {
            guard let entity = world.entity(flow.objectID),
                  let component: FlowRateComponent = entity.component()
            else {
                throw .missingComponent(flow.objectID, "FlowRateComponent")
            }
            guard let estimatedValueIndex = variables.objectIndex[flow.objectID] else {
                throw .corruptedVariableTable
            }
            let adjustedValueIndex = variables.allocate(
                content: .adjustedResult(flow.objectID),
                valueType: flow.valueType,
                name:  "flow_adjusted_\(flow.objectID)"
            )

            // Adjusted: rate actually applied after non-negative-stock scaling
            // Estimated: rate as computed by the flow's formula
            
            let boundFlow = BoundFlow(objectID: flow.objectID,
                                      estimatedValueIndex: estimatedValueIndex,
                                      adjustedValueIndex: adjustedValueIndex,
                                      drains: component.drainsStock,
                                      fills: component.fillsStock)

            boundFlows.append(boundFlow)
        }

        return boundFlows
   }
    
    /// Bind stocks with their variables.
    ///
    func bindStocks(_ stocks: [SimulationObject],
                    flowIndices: [ObjectID:Int], // Index into list of flows
                    world: World)
    throws (PlanningError) -> [BoundStock]
    {
        var result: [BoundStock] = []
        
        for stock in stocks {
            guard let entity = world.entity(stock.objectID),
                  let component: StockComponent = entity.component()
            else {
                throw .missingComponent(stock.objectID, "StockComponent")
            }

            let inflowIndices = component.inflowRates.compactMap { flowIndices[$0] }
            let outflowIndices = component.outflowRates.compactMap { flowIndices[$0] }

            guard inflowIndices.count == component.inflowRates.count &&
                    outflowIndices.count == component.outflowRates.count
            else {
                throw .corruptedComponent(stock.objectID, "StockComponent")
            }
            
            let boundStock = BoundStock(
                objectID: stock.objectID,
                variableIndex: stock.variableIndex,
                allowsNegative: component.allowsNegative,
                inflows: inflowIndices,
                outflows: outflowIndices
            )

            result.append(boundStock)
        }
        
        return result
    }
}
