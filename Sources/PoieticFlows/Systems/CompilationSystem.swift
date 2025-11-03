//
//  CompilationSystem.swift
//  poietic-flows
//
//  Created by Stefan Urbanek on 01/11/2025.
//
import PoieticCore

// TODO: Do state variables need name? Can it be optional?

class StateVariableTable: Component {
    var objectIndex: [ObjectID:Int] = [:]
    var nameIndex: [String:Int] = [:]
    var variables: [StateVariable] = []
    
    func allocate(builtin: BuiltinVariable) -> Int
    {
        let index = self.allocate(content: .builtin(builtin),
                                  valueType: builtin.valueType,
                                  name: builtin.name)
        
        return index
    }

    @discardableResult
    func allocate(content: StateVariable.Content,
                                  valueType: ValueType,
                                  name: String) -> Int
    {
        let index = variables.count
        let variable = StateVariable(index: index,
                                     content: content,
                                     valueType: valueType,
                                     name: name)
        variables.append(variable)
        
        if case let .object(id) = content {
            objectIndex[id] = index
        }
        
        nameIndex[name] = index
        return index
    }
    
    /// Get variable index by name.
    func index(_ name: String) -> Int? {
        return nameIndex[name]
    }
    /// Get variable by name.
    subscript(name: String) -> StateVariable? {
        guard let index = nameIndex[name] else { return nil }
        return variables[index]
    }
    func index(_ objectID: ObjectID) -> Int? {
        return objectIndex[objectID]
    }

    subscript(objectID: ObjectID) -> StateVariable? {
        guard let index = objectIndex[objectID] else { return nil }
        return variables[index]
    }

}

struct SimulationCompilerSystem: System {
    // TODO: Compare with old CompilerError
    internal enum CompilationError: Error, Equatable {
        /// Issue with object has been detected, appended to the list of issues. The caller might
        /// continue with the operation to gather more issues. Criticality of this error is
        /// problem specific.
        case objectIssue
        
        case corruptedComponent(String)
        case missingComponent(String)
        case missingAttribute(String)
        case attributeTypeMismatch(String, ValueType)
        case notImplemented // FIXME: Remove this once happy
    }
    
    nonisolated(unsafe) public static let dependencies: [SystemDependency] = [
        .after(ExpressionParserSystem.self), // Gets us UnboundExpression for each node
        .after(SimulationOrderDependencySystem.self), // Gets us SimulationOrderComponent
        .after(NameCollectorSystem.self), // We need name lookup and object names.
        .after(FlowCollectorSystem.self),
        .after(StockDependencySystem.self),
    ]
    
    let builtinFunctions: [String:Function]
    init() {
        var builtinFunctions: [String:Function] = [:]
        for function in Function.AllBuiltinFunctions {
            builtinFunctions[function.name] = function
        }
        self.builtinFunctions = builtinFunctions
    }
    
    func update(_ frame: RuntimeFrame) throws (InternalSystemError) {
        guard let simOrder = frame.frameComponent(SimulationOrderComponent.self) else {
            return
        }
        
        var hasError: Bool = false
        let variables = StateVariableTable()
        var simulationObjects: [SimulationObject] = []
        var flows: [SimulationObject] = []
        var stocks: [SimulationObject] = []

        let builtins = prepareBuiltins(variables: variables)

        for object in simOrder.objects {
            guard let nameComp: SimObjectNameComponent = frame.component(for: object.objectID),
                  let roleComp: SimulationRoleComponent = frame.component(for: object.objectID)
            else {
                hasError = true
                continue
            }
            
            let rep: ComputationalRepresentation

            do {
                rep = try compileObject(object, frame: frame, variables: variables)
            }
            catch .objectIssue {
                hasError = true
                continue
            }
            catch {
                throw InternalSystemError(self,
                                          message: "Object compilation failed: \(error)",
                                          context: .object(object.objectID))
            }

            let index = variables.allocate(content: .object(object.objectID),
                                           valueType: rep.valueType,
                                           name: nameComp.name)

            let sim = SimulationObject(objectID: object.objectID,
                                       computation: rep,
                                       variableIndex: index,
                                       role: roleComp.role,
                                       valueType: rep.valueType,
                                       name: nameComp.name)
       
            
            simulationObjects.append(sim)
            
            switch roleComp.role {
            case .flow: flows.append(sim)
            case .stock: stocks.append(sim)
            default: break
            }
        }

        guard simOrder.objects.count == simulationObjects.count else {
            throw InternalSystemError(self, message: "Unprocessed simulation objects")
        }

        // If we have errors, finish early without creating the final plan. We are not throwing
        // here, because we did not fail, just the user content is not good for simulation.
        guard !hasError else { return }

        let boundFlows = try bindFlows(flows, frame: frame, variables: variables)
        let boundStocks = try bindStocks(stocks, variables: variables, frame: frame)
        
        // Simulation parameters
        
        let params: SimulationParameters
        if let simInfo = frame.first(trait: Trait.Simulation) {
            params = SimulationParameters(fromObject: simInfo)
        }
        else {
            params = SimulationParameters()
        }

        
        let plan = SimulationPlan(
            simulationObjects: simulationObjects,
            stateVariables: variables.variables,
            builtins: builtins,
            stocks: boundStocks,
            flows: boundFlows,
            charts: [], // FIXME: Relic from the past, remove
            valueBindings: [], // FIXME: Relic from the past, remove
            simulationParameters: params
        )
        
        frame.setFrameComponent(plan)
    }
    
    func prepareBuiltins(variables: StateVariableTable) -> BoundBuiltins {
        // 1. Builtins
        let builtins = BoundBuiltins(
            step: variables.allocate(builtin: .step),
            time: variables.allocate(builtin: .time),
            timeDelta: variables.allocate(builtin: .timeDelta)
        )
        
        return builtins
    }
    
    /// Compile an object into its computational representation.
    ///
    /// - Returns: Computational representation of the object or `nil`.
    ///
    /// nil result if:
    ///
    /// - missing required component
    /// - missing required attribute
    ///
    func compileObject(_ object: ObjectSnapshot,
                       frame: RuntimeFrame,
                       variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation {
        let rep: ComputationalRepresentation
        if object.type.hasTrait(Trait.Formula) {
            rep = try compileFormulaObject(object, frame: frame, variables: variables)
        }
        else if object.type.hasTrait(Trait.GraphicalFunction) {
            throw .notImplemented
            //            rep = try compileGraphicalFunctionNode(object, context: context)
        }
        else if object.type.hasTrait(Trait.Delay) {
            throw .notImplemented
            //            rep = try compileDelayNode(object, context: context)
        }
        else if object.type.hasTrait(Trait.Smooth) {
            throw .notImplemented
            //            rep = try compileSmoothNode(object, context: context)
        }
        else {
            throw .notImplemented
            // Hint: If this error happens, then check one of the the following:
            // - the condition in the stock-flows view method returning
            //   simulation nodes
            // - whether the object design constraints work properly
            // - whether the object design metamodel is stock-flows metamodel
            //   and that it has necessary components
            //
            fatalError("Unknown simulation object type \(object.type.name), object: \(object.objectID)")
        }
        
        return rep
    }
    
    /// - **Forgiveness:** Objects without parsed expression are ignored.
    func compileFormulaObject(_ object: ObjectSnapshot, frame: RuntimeFrame,
                              variables: StateVariableTable)
    throws (CompilationError) -> ComputationalRepresentation
    
    {
        guard let component: ParsedExpressionComponent = frame.component(for: object.objectID) else {
            throw .missingComponent("ParsedExpressionComponent")
        }
        
        // Finally bind the expression.
        //
        let boundExpression: BoundExpression
        do {
            boundExpression = try bindExpression(component.expression,
                                                 variables: variables,
                                                 functions: self.builtinFunctions)
        }
        catch /* ExpressionError */ {
            frame.appendIssue(ObjectIssue.expressionError(error), for: object.objectID)
            throw .objectIssue
        }
        
        return .formula(boundExpression)
    }
    // MARK: - Flow
    
    func bindFlows(_ flows: [SimulationObject], frame: RuntimeFrame, variables: StateVariableTable)
    throws (InternalSystemError) -> [BoundFlow] {
        var boundFlows: [BoundFlow] = []
        
        for flow in flows {
            let boundFlow: BoundFlow
            boundFlow = try bindFlow(flow.objectID,
                                     name: flow.name,
                                     valueType: flow.valueType,
                                     variables: variables,
                                     frame: frame)
            boundFlows.append(boundFlow)
        }
        return boundFlows

    }
    
    func bindFlow(_ objectID: ObjectID,
                  name: String,
                  valueType: ValueType, // rep.valueType
                  variables: StateVariableTable,
                  frame: RuntimeFrame)
    throws (InternalSystemError) -> BoundFlow {
        guard let component: FlowRateComponent = frame.component(for: objectID) else {
            throw InternalSystemError(self,
                                      message: "Missing required component",
                                      context: .frameComponent("FlowRateComponent"))
        }
        guard let objectIndex = variables.objectIndex[objectID] else {
            // TODO: Throw corrupted component
            preconditionFailure()
        }
        let actualIndex = variables.allocate(content: .adjustedResult(objectID),
                                              valueType: valueType,
                                              name:  name)
        let boundFlow = BoundFlow(objectID: objectID,
                                  estimatedValueIndex: objectIndex,
                                  adjustedValueIndex: actualIndex,
                                  priority: component.priority,
                                  drains: component.drainsStock,
                                  fills: component.fillsStock)

        return boundFlow
    }
    
    func bindStocks(_ stocks: [SimulationObject], variables: StateVariableTable, frame: RuntimeFrame)
    throws (InternalSystemError) -> [BoundStock] {
        var result: [BoundStock] = []
        
        for stock in stocks {
            let boundStock: BoundStock
            boundStock = try bindStock(stock.objectID,
                                       variableIndex: stock.variableIndex,
                                       variables: variables,
                                       frame: frame)
            result.append(boundStock)
        }
        return result
    }
    
    func bindStock(_ objectID: ObjectID,
                   variableIndex: Int,
                   variables: StateVariableTable,
                   frame: RuntimeFrame)
    throws (InternalSystemError) -> BoundStock {
        guard let comp = frame.frameComponent(StockDependencyComponent.self) else {
            throw InternalSystemError(self,
                                      message: "Missing component",
                                      context: .frameComponent("StockDependencyComponent"))
        }

        let inflowIndices = comp.inflowRates.compactMap { variables.index($0) }
        let outflowIndices = comp.outflowRates.compactMap { variables.index($0) }

        guard inflowIndices.count == comp.inflowRates.count &&
                outflowIndices.count == comp.outflowRates.count
        else {
            throw InternalSystemError(self,
                                      message: "Corrupted component",
                                      context: .frameComponent("StockDependencyComponent"))
        }
        
        let boundStock = BoundStock(
            objectID: objectID,
            variableIndex: variableIndex,
            allowsNegative: comp.allowsNegative,
            inflows: inflowIndices,
            outflows: outflowIndices
        )
        
        return boundStock

    }
}

