```@meta
CurrentModule = CanvasXpress
```

# CanvasXpress.jl

Julia interface to [CanvasXpress](https://canvasxpress.org) — interactive, self-contained
JavaScript charts driven from Julia tables and matrices. Renders in IJulia/Jupyter, Pluto,
VS Code, Documenter, and standalone HTML files.

CanvasXpress.jl is a thin JSON bridge: it converts your data, serializes the configuration,
and emits the HTML; the charting engine is the CanvasXpress JavaScript bundle, loaded from
cdnjs at display time (or from a local build you point it at for offline use). The call
shape mirrors the R package, so recipes port over directly.

## Installation

```julia
using Pkg
Pkg.add("CanvasXpress")
```

## Quick start

`canvasxpress` takes the data **positionally** (a matrix, a Tables.jl source, or a
pre-built data `Dict`); every keyword becomes a config parameter.

```julia
using CanvasXpress

data = [10 20 30 40;
        50 60 70 80;
        90 15 25 35]            # rows are variables, columns are samples

p = canvasxpress(data;
                 vars = ["g1", "g2", "g3"],
                 smps = ["s1", "s2", "s3", "s4"],
                 smpAnnot = Dict("Treatment" => ["A", "B", "A", "B"]),
                 graphType = "Heatmap",
                 title = "Expression")

display(p)                    # IJulia / Pluto / VS Code / Documenter
savehtml(p, "chart.html")     # self-contained page
```

A Tables.jl source works too — one column holds the variable ids:

```julia
tbl = (gene = ["g1", "g2"], s1 = [1, 3], s2 = [2, 4])
p = canvasxpress(tbl; rownames = :gene, graphType = "Bar")
```

## Offline rendering

By default the engine is loaded from cdnjs. For offline use, either download the pinned
engine once with [`download_engine!`](@ref), or point [`set_engine_dir!`](@ref) at a local
CanvasXpress build:

```julia
download_engine!()            # fetch + cache the pinned engine, then use it offline
savehtml(p, "chart.html")     # self-contained, no network
```

## Configuration reference

[`cx_config_params`](@ref) returns the full catalog of configuration parameters, and
`canvasxpress(...; validate = true)` checks your config against it, warning on unknown keys,
bad enum values, and wrong types (`validate = :strict` throws instead).

## API

```@autodocs
Modules = [CanvasXpress]
Private = false
```
