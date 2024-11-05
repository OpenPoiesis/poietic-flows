# Compiled Model and Compiler

Compiler creates a compiled model, which is an internal representation of
a design that can be simulated.

## Overview

A design represents user's idea, user's creation. To be able to perform the
computation, the design has to be validated and converted into a
representation understandable by a simulator. That conversion is done by
the compiler.

![Compiler Overview](compiler-overview)


## Topics

### Compiler and Compiled Model

- ``Compiler``
- ``CompiledModel``
- ``StockFlowView``

### Compiled Model Components

- ``BuiltinVariable``
- ``ChartSeries``
- ``Chart``
- ``CompiledBuiltin``
- ``CompiledControlBinding``
- ``CompiledDelay``
- ``CompiledSmooth``
- ``CompiledGraphicalFunction``
- ``CompiledStock``
- ``ComputationalRepresentation``
- ``SimulationDefaults``
- ``SimulationObject``
- ``SimulationVariableType``
- ``StateVariable``
- ``StateVariableContent``
- ``StockAdjacency``

### Systems

Note: This is part of experimental architecture.

- ``FormulaCompilerSystem``
- ``ParsedFormulaComponent``

### Errors

- ``CompilerError``
- ``ObjectIssue``
- ``ParameterStatus``

### Bound Expression

- ``BoundExpression``
- ``BoundVariable``
- ``ExpressionError``
- ``bindExpression(_:variables:names:functions:)``
- ``ParsedFormula``
