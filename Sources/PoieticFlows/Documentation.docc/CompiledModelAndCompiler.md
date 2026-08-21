# Simulation Planning and Simulation Plan

To perform a simulation, the computer needs to understand how it is to be performed and needs to
make sure that it is possible to simulate the model. The simulation plan is computer-oriented
representation of the model, derived from the user-oriented representation, which is `Design`.


## Overview

A design represents user's idea, user's creation. To be able to perform the computation,
the design has to be validated and converted into a representation understandable by a simulator.
That conversion from `Design` to ``SimulationPlan`` is done by the `SimulationPlanningSystem`
through multiple steps:

1. Arithmetic expressions are parsed by `ExpressionParserSystem`.
2. Computation order is determined in ``ComputationOrderSystem``.
3. Object names are resolved and bi-directional object-name mappings are created in ``NameResolutionSystem``.
4. Flows and stocks are collected and resolved in the ``StockFlowTopologySystem``.
5. The simulation plan is finalised from all the components created by the above systems.

![Compiler Overview](compiler-overview)

## Topics

### Simulation Plan

- ``SimulationPlan``
- ``SimulationObject``
- ``StateVariable``
- ``BoundBuiltins``
- ``BoundStock``
- ``BoundFlow``
- ``SimulationSettings``
- ``IssueIdentifier``

### Compiled Model Components

- ``SimulationOrder``
- ``SimulationRole``
- ``SimulationNameLookup``
- ``SimulationName``
- ``FlowRateComponent``
- ``StockComponent``

- ``BuiltinVariable``
- ``Chart``

### Other

- ``BoundDelay``
- ``BoundSmooth``
- ``BoundGraphicalFunction``
- ``BoundStock``
- ``ComputationalRepresentation``
- ``ResolvedParameters``

### Systems


- ``SimulationPlanningSystem``
- ``ComputationOrderSystem``
- ``NameResolutionSystem``
- ``StockFlowTopologySystem``
- ``ParameterResolutionSystem``

#### Schedule Collections:

- ``SimulationPlanningSystems``
- ``SimulationRunningSystems``

### Bound Expression

- ``BoundExpression``
- ``BoundVariable``

