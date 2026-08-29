# Simulation

The simulation is run according to the simulation plan, which describes order in which the objects
are evaluated, how the computation is performed and where in the simulation state the variables
live.

## Overview

The object that performs the simulation is ``StockFlowSimulation``. It reads the simulation plan
and evaluates simulation objects according to specified order.


### Simulation System

In your application you run the ``StockFlowSimulationSystem`` within a schedule. You rarely need to
use the simulation object directly. The system does the following:

1. Reads the ``SimulationSettings`` singleton to set-up time, time delta and solver type. If not
   present, then default settings are used.
2. Reads the ``ScenarioParameters`` that is used to override object values during initialisation.
3. Initialises a new simulation state.
4. Runs the simulation for given number of steps.
5. Constructs a simulation result ``SimulationResult`` and sets it as a singleton.

If the simulation was not successful, the simulation result is not set and if existed before the
system was run, it will be removed.


## Computation

The simulation is performed as follows:

**Initialisation**

1. prepare new simulation state
2. set values of builtins in the state
3. FOR EACH simulation object in the order of computational dependency:
    - _Stocks_, _Auxiliaries_, _Flow Rates_: compute initial value by evaluating the formula.
    - _Graphical function_: get initial value according to the function definition.
    - _Delay_, _Smooth_: If the object has initial value is set, initialise it to the value,
        otherwise use value from the parameter.


**Simulation Step: Euler Integration**

1. Prepare a new simulation state.
2. Get stock values from the t-1 (previous step).
3. Get flows estimation from the t-1 (previous step).
4. Compute adjusted flows from flows estimates and stock values.
    1. FOR each stock:
        1. total inflow estimate = ∑ flow rates filling the stock
        2. total outflow estimate = ∑ flow rates draining the stock
        3. Compute adjusted flows by scaling:
            - IF flow scaling is _outflows first_: 

              scale = min(1, current / outflow)

              adjustedₙ = estimatedₙ * scale
                
            - IF flow scaling is _inflows first_: 

              available = current stock + inflow

              scale = min(1, available / outflow)

              adjustedₙ = estimatedₙ * scale

2. Returns a vector of adjusted flow rates.
5. Compute derivatives Δstock from adjusted flows and stocks.
    1. FOR each stock:
        1. inflow = total ∑ of adjusted stock's inflows
        2. outflow = total ∑ of adjusted stock's outflows
        3. compute net flow:
            - IF allows negative: net flow = (inflow - outflow) \* timeDelta
            - ELSE: net flow = max(-current, (inflow - outflow) \* timeDelta)
    2. Returns a vector of Δstock
6. Adjust stocks: stockₙ(t) = stockₙ(t-1) + Δstockₙ
7. Update auxiliaries and flow rates.
8. Write adjusted flow values to the simulation state.

- Note: Runge Kutta 4 solver (`rk4`) follows the same pattern with four intermediate evaluations.


### Simulation Parameters

Simulation parameters can be provided during initialisation
(``StockFlowSimulation/initialize(time:timeDelta:parameters:)``). They override initial value
of all objects and simulation run values of some of the objects. 

For objects where the parameter is **not provided**: the object value is evaluated as specified
in its computational representation.

For objects where the parameter is **provided**: the object is initialised to given parameter
value. For accumulator objects (stock, delay, smooth) the parameter is used only to set
the initial value, later during the computation the value is disregarded. For objects that
are not accumulators (flow rates, auxiliaries, graphical function, ...) the parameter value
is preserved as their constant through the whole simulation run.

## Results

The ``StockFlowSimulationSystem`` runs the simulation and if the simulation was successful
(no evaluation errors), then it produces a ``SimulationResult`` singleton. The result contains
states for each step of the simulation.

The results can be further processed and distributed on entities for presentation.

## Topics

### Simulation

- ``StockFlowSimulation``
- ``StockFlowSimulationSystem``
- ``SimulationSettingsSystem``
- ``SimulationState``
- ``NumericVector``
- ``GraphicalFunction``
- ``SimulationError``
- ``RegularTimeSeries``
- ``BuiltinVariable``

### Result

- ``SimulationResult``
- ``SimulationResultView``

### Components

- ``SimulationSettings``
- ``ScenarioParameters``

