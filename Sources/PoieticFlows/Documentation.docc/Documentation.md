# ``PoieticFlows``

Stock and Flow domain package for PoieticCore.


## Overview

_Stock and Flow_ models are networks of stocks that accumulate material (or energy, value,...),
flows that move the material, and of other meaningful connections.
See [Stock and Flow](https://en.wikipedia.org/wiki/Stock_and_flow).

This is a methodology package, not a tool nor an application. This package is for developers
that want to build applications presenting Stock and Flow scenarios or to build tools for modellers.

### Features

- **Metamodel**: Stock, FlowRate, Auxiliary, GraphicalFunction, Delay, Smooth and related
  edges. See <doc:Metamodel> with full list of nodes and edges with their description.
- **Planning Pipeline**: Collection of systems that analyse the design and turn it into a
  computable ``SimulationPlan``. See <doc:PlanAndPlanning>.
- **Simulation**: [Euler](https://en.wikipedia.org/wiki/Euler_method)
      [Runge-Kutta 4](https://en.wikipedia.org/wiki/Runge–Kutta_methods) solvers, support for
    non-negative stock constraints. See <doc:SimulationRunning>.
- **Issue Reporting**: User errors are collected as issues with hints and related objects.

The relationship of the components and the flow of data between them is captured
in the following diagram:

![Flows Components Overview](flows-overview)

### Example

```swift
    import Foundation
    import PoieticCore
    import PoieticFlows
    
    // 1. Load the design from a file.
    let url = URL(fileURLWithPath: "predator_prey.poietic")
    let design = try DesignStore(url: url).load(metamodel: StockFlowMetamodel)
    
    guard let plane = design.currentPlane else {
        print("The design has no current plane.")
        exit(1)
    }
    
    // 2. Create a world for the plane and prepare the two schedules.
    let world = World(plane: plane)
    
    // 3. Create the simulation plan.
    try world.run(systems: SimulationPlanningSystems)
    
    guard let plan: SimulationPlan = world.singleton() else {
        // The model has issues – present them to the user.
        for (id, issues) in world.issues {
            print("Object \(id):")
            for issue in issues { print("  \(issue)") }
        }
        exit(1)
    }
    
    // 4. Run the simulation.
    try world.run(systems: SimulationRunningSystems)
    
    guard let result: SimulationResult = world.singleton() else {
        print("The simulation failed.")
        exit(1)
    }
    
    // 5. Print the results.
    let view = SimulationResultView(result: result, plan: plan,
                                    columns: ["time"] + plan.objectNames)

    print(view.columnNames.joined(separator: "\t"))
    for row in view {
        print(row.stringValues().joined(separator: "\t"))
    }
```

## Topics

- <doc:Metamodel>
- <doc:PlanAndPlanning>
- <doc:SimulationRunning>
- <doc:Formulas>

- ``StockFlowMetamodel``

