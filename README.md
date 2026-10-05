# CanvasXpress.jl

[![CI](https://github.com/neuhausi/CanvasXpress.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/neuhausi/CanvasXpress.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/neuhausi/CanvasXpress.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/neuhausi/CanvasXpress.jl)
[![docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://neuhausi.github.io/CanvasXpress.jl/stable/)

Julia interface to [CanvasXpress](https://canvasxpress.org) — interactive, self-contained
JavaScript charts driven from Julia tables and matrices. Renders in IJulia/Jupyter, Pluto,
VS Code, Documenter, and standalone HTML files.

CanvasXpress.jl is a thin JSON bridge: it converts your data, serializes the configuration,
and emits the HTML; the charting engine is the CanvasXpress JavaScript bundle, loaded from
[cdnjs](https://cdnjs.com/libraries/canvasXpress) at display time (or from a local build you
point it at for offline use). The call shape mirrors the R package, so recipes port over
directly.

## Install

```julia
using Pkg
Pkg.add("CanvasXpress")
```

## Usage

`canvasxpress` takes the data **positionally** (a matrix, a Tables.jl source, or a pre-built
data `Dict`); every keyword becomes a config parameter.

```julia
using CanvasXpress

# rows are variables, columns are samples
data = [10 20 30 40;
        50 60 70 80;
        90 15 25 35]

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
using CanvasXpress

tbl = (gene = ["g1", "g2"], s1 = [1, 3], s2 = [2, 4])
p = canvasxpress(tbl; rownames = :gene, graphType = "Bar")
display(p)
```

An exported `canvasXpress` alias is provided so R-style calls read the same in Julia.
`cx_config_params()` returns the full catalog of configuration parameters, and
`canvasxpress(...; validate = true)` checks your config against it.

## Offline rendering

By default the engine is loaded from cdnjs. For offline use, point the package at a local
CanvasXpress build:

```julia
set_engine_dir!("/path/to/dir/with/canvasXpress.min.js")  # inlined into the HTML
savehtml(p, "chart.html")                                  # self-contained, no network
```

## Static images

`savefig(p, "chart.png")` renders a PNG via the [`cxplot`](https://www.npmjs.com/package/cxplot)
CLI (`npm i -g cxplot`) or the `ghcr.io/neuhausi/cxplot` container.

## License

The Julia source in this repository is released under the [MIT License](LICENSE). The
CanvasXpress JavaScript engine it loads at runtime is distributed separately (via cdnjs)
under its own [CanvasXpress license terms](https://canvasxpress.org/license.html).
