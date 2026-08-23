# Poietic Flows

Stock and Flow modelling and simulation on top of
[PoieticCore](https://github.com/OpenPoiesis/poietic-tool). A domain package of
OpenPoiesis toolkit.

Models are networks of stocks that accumulate, flows that move material (or energy, value, ...),
and of other meaningful connections.
See [Stock and Flow](https://en.wikipedia.org/wiki/Stock_and_flow).

## Features

- **Metamodel**: Stock, FlowRate, Auxiliary, GraphicalFunction, Delay, Smooth and related
  edges.
- **Planning Pipeline**: Collection of systems that analyse the design and turn it into a
  computable `SimulationPlan`
- **Simulation**: [Euler](https://en.wikipedia.org/wiki/Euler_method)
      [Runge-Kutta 4](https://en.wikipedia.org/wiki/Runge–Kutta_methods) solvers, support for non-negative stock constraints.
- **Issue Reporting**: User errors are collected as issues with hints and related objects.


## Application Examples

- [Poietic Tool](https://github.com/OpenPoiesis/poietic-tool) – A command-line tool for editing
  and running Stock and Flow models.
- [Poietic Playground](https://github.com/OpenPoiesis/poietic-playground) – A CAD-like application
  where you can visually edit, inspect and run models.

- [Examples](https://github.com/OpenPoiesis/poietic-examples) – Repository with example models.

## Documentation

- Stock and Flow Simulation: [**PoieticFlows**](https://openpoiesis.github.io/poietic-flows/documentation/poieticflows/)

Shortcuts:

- [Metamodel](https://openpoiesis.github.io/poietic-flows/documentation/poieticflows/metamodel)
- [Simulation Planning](https://openpoiesis.github.io/poietic-flows/documentation/poieticflows/planandplanning)
- [Computation](https://openpoiesis.github.io/poietic-flows/documentation/poieticflows/simulationrunning)
- [Formulas](https://openpoiesis.github.io/poietic-flows/documentation/poieticflows/formulas)

### Related packages:

- [PoieticCore](https://openpoiesis.github.io/poietic-core/documentation/poieticcore/) – Virtual laboratory foundation
- [Diagramming](https://openpoiesis.github.io/poietic-diagram/documentation/diagramming/)
  – Package for creating diagrammatic representations of models.

## Contributing

_All humans are more than welcome to contribute to the project._

Read more in the [Contribution Policy](CONTRIBUTING.md) file.


## Author

[Stefan Urbanek](mailto:stefan.urbanek@gmail.com)

