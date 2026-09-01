# Formulas

Formulas define an arithmetic computation of a node.

## Overview

Computation of nodes such as stocks, flows or auxiliaries is defined by an
arithmetic formula. The formula is provided as a string in a node's attribute
`formula`.

For example an auxiliary node with a formula `account * rate`:

```swift
let plane: TransientPlane
let interest = plane.createNode(ObjectType.Auxiliary,
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
| `^` | Power |

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
| `exp(x)` | Natural exponent of _x_ |
| `sqrt(x)` | Square root of _x_ |
| `sum(a,...)` | Sum of multiple values |
| `min(a,b,...)` | Minimum value from a list of values |
| `max(a,b,...)` | Maximum value from a list of values |

Logical functions:

| Name | Description |
| ---- | ---- |
| `if(cond,tval,fval)` | Returns _tval_ if the condition _cond_ is true, otherwise _fval_ |
| `not(a)` | Returns negation of boolean value _a_ |
| `or(a,b,...)` | Returns logical _OR_ of all the arguments – true if at least one is true |
| `and(a,b,...)` | Returns logical _AND_ of all the arguments – true if all arguments are true |

### Built-in Simulation Variables

| Name | Description |
| ---- | ---- |
| `time` | Current simulation time |
| `time_delta` | Time delta (as specified during initialisation) |
| `simulation_step` | Current simulation step |

## Variables and Nodes

Formulas can reference values in other nodes by using their name. The node that the formula
node refers to, must be connected with a `Parameter` connection. For example,
if a node has a formula `price * 0.1`, then it must be connected from the `price` node.

If the node names contain spaces or other characters, their name must be quoted using
curly brackets: `{birth rate} * 0.5` or `{population growth} / 10`. Names are case insensitive,
spaces are trimmed and collapsed. Underscore `_` is equivalent to a space. The following
names are considered equal:

- `Birth Rate`
- `birth rate`
- `birth_rate`
- ` BIRTH  RATE `
