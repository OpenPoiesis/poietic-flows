# Formulas

Formulas define an arithmetic computation of a node.

## Overview

Computation of nodes such as stocks, flows or auxiliaries is defined by an
arithmetic formula. The formula is provided as a string in a node's attribute
`formula`.

For example an auxiliary node with a formula `account * rate`:

```swift
let frame: TransientFrame

let interest = frame.createNode(ObjectType.Auxiliary,
                                name: "interest",
                                attributes: ["formula": "account * rate"])

```

### Operators

Binary arithmetic operators:

| Operator | Description |
| ---- | ---- |
| `+` | Addition |
| `-` | Subtraction |
| `*` | Multiplication |
| `/` | Division |
| `%` | Remainder after division |

Comparison operators:

| Operator | Description |
| ---- | ---- |
| `==` | Equal |
| `!=` | Not equal |
| `>` | Greater than |
| `>=` | Greater or equal than |
| `<` | Less than |
| `<=` | Less or equal than |

### Built-in Functions

Arithmetic functions:

| Name | Description |
| ---- | ---- | 
| `abs(x)` | Absolute value |
| `floor(x)` | Rounding downwards to the nearest integer |
| `ceiling(x)` | Rounding upwards to the nearest integer |
| `round(x)` | Rounding to the nearest integer |
| `power(x,e)` | Power of _x_ to _e_ |
| `sum(a,...)` | Sum of multiple values |
| `min(a,b,...)` | Minimum value from a list of values |
| `min(a,b,...)` | Maximum value from a list of values |

Logical functions:

| Name | Description |
| ---- | ---- |
| `if(cond,tval,fval)` | Returns _tval_ if the condition _cond_ is true, otherwise _fval_ |
| `not(a)` | Returns negation of boolean value _a_ |
| `or(a,b,...)` | Returns logical _OR_ of all the arguments – true if at least one is true |
| `and(a,b,...)` | Returns logical _AND_ of all the arguments – true if all arguments are true |

### Built-in Variables

| Name | Description |
| ---- | ---- |
| `time` | Current simulation time |
| `time_delta` | Time delta (as specified during initialisation) |

## Variables and Nodes

Each variable that represents another node must have a corresponding `Parameter`
edge. The `Parameter` edge originates in the node containing the value
and ends in the node having the formula using the value.

