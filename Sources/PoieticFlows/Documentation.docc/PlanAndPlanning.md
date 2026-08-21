# Simulation Plan and Planning

To perform a simulation, the computer needs to understand how it is to be performed and needs to
be sure that it is possible to simulate the model. The simulation plan is computer-oriented
representation of the model, derived from the user-oriented representation in the model design.

## Overview

A design represents user's idea, user's creation. To be able to perform the computation,
the design has to be validated and converted into a representation understandable by the simulator.
The interpretable representation is called ``SimulationPlan`` and contains specification how each
of the objects is to be computed, in which order and where the computed values are stored.

![Planning Overview](planning-overview)

The conversion from `Design` to ``SimulationPlan`` is done by the `SimulationPlanningSystem`
through multiple steps:

1. Arithmetic expressions are parsed by `ExpressionParserSystem` (provided by the PoieticCore package).
2. Parameters are resolved with ``ComputationOrderSystem``.
3. Computation order and simulation role of objects is determined in ``ParameterResolutionSystem``.
4. Object names are resolved and validated in ``NameResolutionSystem``.
5. Flows and stocks are collected and resolved in the ``StockFlowTopologySystem``.
6. The simulation plan is finalised from all the components by the ``SimulationPlanningSystem``.

In addition to the simulation plan, simulation settings (initial time, time delta, etc.) are
extracted from the model for the simulator in the ``SimulationSettingsSystem``

![Planning Systems](planning-systems)

## Topics

### Simulation Plan

- ``SimulationPlan``
- ``SimulationObject``
- ``ComputationalRepresentation``
- ``StateVariable``
- ``SimulationPlanningSystem``
- ``SimulationPlanner``
- ``PlanningError``

### Plan Analysis

- ``ComputationOrderSystem``
- ``NameResolutionSystem``
- ``StockFlowTopologySystem``
- ``ParameterResolutionSystem``

### Plan Internals

- ``BoundBuiltins``
- ``BoundStock``
- ``BoundFlow``
- ``BoundDelay``
- ``BoundSmooth``
- ``BoundGraphicalFunction``
- ``IssueIdentifier``

### Components

- ``FlowRate``
- ``Stock``
- ``SimulationOrder``
- ``SimulationRole``
- ``SimulationNameLookup``
- ``SimulationName``
- ``Chart``
- ``ResolvedParameters``

#### Schedule Collections:

- ``SimulationPlanningSystems``
- ``SimulationRunningSystems``

### Bound Expression

- ``BoundExpression``
