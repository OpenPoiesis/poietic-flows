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

## Planning Steps

The conversion from `Design` to ``SimulationPlan`` is done by the `SimulationPlanningSystem`
through multiple steps:

1. Arithmetic expressions are parsed by `ExpressionParserSystem` (provided by the PoieticCore package).
2. Parameters are resolved with ``ParameterResolutionSystem``.
3. Computation order and simulation role of objects is determined in ``ComputationOrderSystem``.
4. Object names are resolved and validated in ``NameResolutionSystem``.
5. Flows and stocks are collected and resolved in the ``StockFlowTopologySystem``.
6. The simulation plan is finalised from all the components by the ``SimulationPlanningSystem``.

In addition to the simulation plan, simulation settings (initial time, time delta, etc.) are
extracted from the model for the simulator in the ``SimulationSettingsSystem``

![Planning Systems](planning-systems)

## Issues

If there are any semantic issues with the user's model, the ``SimulationPlanner`` and systems
leading to it attach the issues to the offending entity. If there are any issues set for
objects involved in the simulation, then the planner will not produce a plan. Application
is expected to display list of issues with the model to the user, preferably guiding the user
to the object with an issue.

Application should check for `World.hasIssues` and then present `RuntimeEntity.issues` to the user.
(Functionality is provided in the PoieticCore package.)

The planner and related systems might produce the following issues:

| Identifier | Description |
| --- | --- |
| `unknown_parameter` | Parameter used in the formula is not known or not connected |
| `unused_input` | Parameter is connected but unused in the node's formula |
| `missing_required_parameter` | Node requires a parameter and it is not connected | 
| `too_many_parameters` | More parameters than required for given node (delay, smooth or graphical function) |
| `duplicate_name` | Multiple nodes have the same name |
| `empty_name` | Node name is empty or contains only whitespaces (visually empty) |
| `reserved_name` | Node name is the same as one of reserved built-in variable names |
| `computation_cycle` | Nodes are connected in a way that they for cyclic dependency |
| `invalid_parameter_type` | Invalid parameter data type (for delay, smooth or graphical function) |

- Note: Formula parameters must be connected to the nodes using them. This is a model semantics
  requirement. The planner could resolve parameters by name alone, but explicit connections
  are required so user can visually reason about the model.
  The two issues `unknown_parameter` and `unused_input` capture that requirement.

You might also find the following errors that are produced by the `ExpressionParserSystem` from
PoieticCore package. They all have prefix `expression` so your application can use that hint
for visual indication of the error.


| Identifier | Description |
| --- | --- |
| `expression.unknown_variable` | Unknown variable name used |
| `expression.unknown_function` | Unknown function name used |
| `expression.invalid_argument_count` | Number of function arguments do not match function requirements |
| `expression.argument_type_mismatch` | Type of argument for a function does not match (for example used bool where numeric is expected) |
| `expression.invalid_character_in_number` | Malformed number |
| `expression.number_expected` | Expected a number character |
| `expression.unexpected_character` | Unexpected character |
| `expression.missing_right_parenthesis` |  Left parenthesis is not paired with right parenthesis |
| `expression.expression_expected` | Expression expected (likely after a binary operator) |
| `expression.unexpected_token` | Unexpected token |


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
