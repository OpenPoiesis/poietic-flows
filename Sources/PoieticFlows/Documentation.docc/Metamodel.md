# Stock and Flow Metamodel

Description of the Stock and Flow domain.

## Overview

The Stock and Flow model domain (metamodel) recognises the following node
types that define the computation:


- Note: Users of your application can explore the metamodel using the
  [command-line tool `poietic`](https://github.com/openpoiesis/poietic-tool) by running
  the command: `poietic metamodel`

| Type | Represents | Use | 
|-----|-------------|-----|
| `Stock` | An amount (of a material) in a container, reservoir, or a pool. | computation | 
| `FlowRate` | Rate by which connected container is filled or drained. | computation |
| `Auxiliary` | Auxiliary computation or a constant | computation | 
| `GraphicalFunction` | Function defined by a set of points | computation |
| `Delay` | Delay of a value by a specific number of time units | computation |
| `Smooth` | Exponential smoothing of input | computation |
| `Chart` | Visual output in a form of a chart with one or multiple series | visualisation |
| `Control` | Visual input node | experimentation |
| `Note` | User comment | none |

The edges in the domain are:


| Type | Represents |
| ---- | ---- |
| `Flow` | What a flow drains/fills |
| `Parameter` | Connection between an auxiliary and other computation node |
| `ChartSeries` | Series of a chart |
| `ValueBinding` | Binding between a control and a value |


The following table contains edge rules (in the metamodel) that need to be satisfied so that the
model is valid. For example: _A FlowRate can fill at most one stock and drain at most one stock_.

| Edge | Origin cardinality | Origin | Target cardinality | Target
| --- | --- | --- | --- | ---
| Flow | one | FlowRate | many | trait Stock
| Flow | one | trait Stock | many | FlowRate
| Parameter | many | Auxiliary or Stock or FlowRate | one | Graphical Function
| Parameter | many | Auxiliary or Stock or FlowRate | many | Auxiliary or Stock or FlowRate
| Comment   | many | any   | many | any
| ValueBinding   | many | Control   |  many | any
| ChartSeries | many | Chart | many | trait ComputedValue


## Example Model

The following example shows how to create a simple bank account model. First we
create the nodes:

```swift
let design = Design(metamodel: StockFlowMetamodel)
let plane = design.createPlane()

let account = plane.createNode(ObjectType.Stock,
                               name: "account",
                               attributes: ["formula": "100"])

let rate = plane.createNode(ObjectType.Auxiliary,
                            name: "rate",
                            attributes: ["formula": "0.02"])

let interest = plane.createNode(ObjectType.Auxiliary,
                                name: "interest",
                                attributes: ["formula": "account * rate"])

```

The nodes need to be connected:

```swift
plane.createEdge(ObjectType.Parameter, origin: rate, target: interest)
plane.createEdge(ObjectType.Parameter, origin: account, target: interest)
plane.createEdge(ObjectType.Flow, origin: interest, target: account)
```

- Note: Typically you would not be creating detailed models by hand like in the
  above example. The purpose of the library is to provide functionality for
  applications that aid in model design.

- SeeAlso: [Repository of model examples](https://github.com/OpenPoiesis/poietic-examples)

## Attributes

### Stock

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `formula` | string | Initial stock value |
| `allows_negative` | bool | Flag whether the stock can contain a negative value |

### Flow Rate

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `formula` | string | Flow rate computation |

### Auxiliary

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `formula` | string | Constant or an auxiliary computation formula |

### Graphical Function

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `interpolation_method` | string | Method of interpolation for values between the points |
| `graphical_function_points` | array of points | Points of the graphical function |

Available interpolation methods: `step`, `linear`, `cubic`, `nearest`.


Example:
```swift
let points: [Points] = [ /* list of Points */ ]
let yield = plane.createNode(ObjectType.Auxiliary,
                                name: "yield",
                                attributes: [
                                    "graphical_function_points": points
                                ])
```

### Delay

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `delay_duration` | double | Delay duration in steps. |


### Smooth

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `window_time` | double | Averaging window time |

The computation is as follows: _sₜ = α*xₜ + (1 - α) * sₜ₋₁_ Where:
_x_ is input value, _s_: smoothing value and _α = Δt / window_time_


### Step

There is no step node, however it can be implemented using an auxiliary node
with a formula: `"if(time < step_time, initial_value, step_value)"` where
the `step_time` is a time when the step occurs.

For example `"if(time < 20, 0, 1)"` will create a step function with initial
value of 0 and then value of 1 from time 20 onwards.


### Chart

Currently there are no attributes for charts.


### Control

Control is a node that can be used by graphical applications to provide
user-interface for controlling values of other nodes.

Controls types are not currently specified.

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `value` | double | Value of the target node |
| `control_type` | string | Visual type of the control |
| `min_value` | double | Minimum allowed value of the target variable |
| `max_value` | double | Maximum allowed value of the target variable |
| `step_value` | double | Step of a slider control |
| `value_format` | string | Display format of the value |



### Simulation

Simulation node specifies characteristics of a simulation. There should be only
one node of this type in the design. If multiple Simulation nodes are present,
then one is chosen arbitrarily.

Simulation node is not required to be present, but might be in the future.

| Attribute | Type | Description |
| ---- | ---- | ---- |
| `initial_time` | double | Initial simulation time |
| `end_time` | double | Final simulation time |
| `time_delta` | double | Simulation step time delta |
| `solver_type` | string | Solver to use: `euler`, `rk4` |
