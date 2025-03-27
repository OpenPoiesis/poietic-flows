//
//  File.swift
//  
//
//  Created by Stefan Urbanek on 11/07/2022.
//

// Prototyping functions - to be used only during development
//


#if false

extension MutableGraph {
    func createStock(name: String, expression: String) -> ObjectID {
        let node = createNode(FlowsMetamodel.Stock,
                              name: name,
                              traits: [FormulaComponent(expression: expression)])
        return node
    }
    
    func createAux(name: String, expression: String) -> ObjectID {
        let node = createNode(FlowsMetamodel.Auxiliary,
                              name: name,
                              traits: [FormulaComponent(expression: expression)])
        return node
    }
    func createFlow(name: String, expression: String) -> ObjectID {
        let node = createNode(FlowsMetamodel.Flow,
                              name: name,
                              traits: [FormulaComponent(expression: expression)])
        return node
    }
    
    func connectParameter(from origin: ObjectID, to target: ObjectID) {
        self.createEdge(FlowsMetamodel.Parameter,
                         origin: origin,
                         target: target,
                         traits: [])
    }
    
    func connectOutflow(from origin: ObjectID, to target: ObjectID) {
        self.createEdge(FlowsMetamodel.Drains,
                         origin: origin,
                         target: target,
                         traits: [])
    }

    func connectInflow(from origin: ObjectID, to target: ObjectID) {
        self.createEdge(FlowsMetamodel.Fills,
                         origin: origin,
                         target: target,
                         traits: [])
    }
}


/// Create a demo model in a design.
///
/// This function creates a
/// [Lotka-Volterra](https://en.wikipedia.org/wiki/Lotka–Volterra_equations)
/// model with two stocks: sharks and fish, and four flows: births and deaths
/// of both of the entities represented by the stocks.
///
/// Use:
///
/// ```swift
/// let design: Design
///
/// CreatePredatorPreyDemo(in: design)
///
/// ```
///
/// The created model is accepted into the design and is available
/// as the last frame in the design frame history, also known as the
/// "current frame".
///
public func CreatePredatorPreyDemo(in design: Design) throws {
    let frame = design.deriveFrame()
    let frame = frame.mutableGraph
    
    let fish = frame.createStock(name: "fish", expression: "1000")
    let shark = frame.createStock(name: "shark", expression: "10")

    let fish_birth_rate = frame.createAux(name: "fish_birth_rate", expression: "0.01" )
    let shark_birth_rate = frame.createAux(name: "shark_birth_rate", expression: "0.6" )
    let shark_efficiency = frame.createAux(name: "shark_efficiency", expression: "0.0003" )
    let shark_death_rate = frame.createAux(name: "shark_death_rate", expression: "0.15" )

    let fish_births = frame.createFlow(name: "fish_births", expression: "fish * fish_birth_rate")
    let shark_births = frame.createFlow(name: "shark_births", expression: "shark * shark_birth_rate * shark_efficiency * fish")
    let fish_deaths = frame.createFlow(name: "fish_deaths", expression: "fish * shark_efficiency * shark")
    let shark_deaths = frame.createFlow(name: "shark_deaths", expression: "shark_death_rate * shark")

    frame.connectParameter(from: fish_birth_rate, to: fish_births)
    frame.connectParameter(from: fish, to: fish_births)
    frame.connectInflow(from: fish_births, to: fish)

    frame.connectParameter(from: shark_birth_rate, to: shark_births)
    frame.connectParameter(from: shark, to: shark_births)
    frame.connectParameter(from: shark_efficiency, to: shark_births)
    frame.connectParameter(from: fish, to: shark_births)
    frame.connectInflow(from: shark_births, to: shark)

    frame.connectParameter(from: fish, to: fish_deaths)
    frame.connectParameter(from: shark_efficiency, to: fish_deaths)
    frame.connectParameter(from: shark, to: fish_deaths)
    frame.connectOutflow(from: fish, to: fish_deaths)

    frame.connectParameter(from: shark, to: shark_deaths)
    frame.connectParameter(from: shark_death_rate, to: shark_deaths)
    frame.connectOutflow(from: shark, to: shark_deaths)

    try design.accept(frame)
}

#endif
