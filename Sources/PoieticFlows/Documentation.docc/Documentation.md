# ``PoieticFlows``

Poietic package for modelling and simulation _Stock and Flow_ models.

## Overview

The PoieticFlows package provides a domain model and a simulation functionality
for [Stock and Flow](https://en.wikipedia.org/wiki/Stock_and_flow) models.

The major components and capabilities of the Flows package are:

- Stock and Flow metamodel, object types and validation constraints
- Design compiler for creating computable model representation
- Simulator and solver for performing the simulation

The relationship of the components and the flow of data between them is caputred
in the following diagram:

![Flows Components Overview](flows-overview)

- Core computational nodes: `Stock`, `Flow` and `Auxiliary`
- `GraphicalFunction` node for a function that is represented
 by a graph – set of points in a 2D plane.
- Special nodes: `Delay` and `Smooth`
- Component for arithmetic formulas `Formula` for all core 
  computational nodes.
- Built-in functions: `abs`, `floor`, `ceiling`, `round`, `power`, `sum`, `min`,
  `max`
- Included [Euler](https://en.wikipedia.org/wiki/Euler_method)
  and [RK4](https://en.wikipedia.org/wiki/Runge–Kutta_methods) solvers.

## Topics

- <doc:Metamodel>
- <doc:Formulas>
- <doc:CompiledModelAndCompiler>
- <doc:Simulation>
- ``FlowsMetamodel``

