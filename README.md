# CanvasXpress.jl

[![CI](https://github.com/neuhausi/CanvasXpress.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/neuhausi/CanvasXpress.jl/actions/workflows/CI.yml)

Julia interface to [CanvasXpress](https://canvasxpress.org) — interactive, self-contained
JavaScript charts driven from Julia tables and matrices. Renders in IJulia/Jupyter, Pluto,
VS Code, Documenter, and plain HTML files.

The package is a thin JSON bridge: the charting engine is the CanvasXpress JavaScript bundle,
and Julia converts your data, serializes the configuration, and emits the HTML. The call shape
mirrors the R package so existing recipes port over directly.

> **Status: early scaffold.** The data-conversion and rendering layers are under active
> development. The API below is the target surface.

## Install

```julia
using Pkg
Pkg.add("CanvasXpress")
```

## Usage

```julia
using CanvasXpress

p = canvasxpress(; data = Dict("y" => Dict("vars" => ["g1", "g2"],
                                           "smps" => ["s1", "s2"],
                                           "data" => [[1, 2], [3, 4]])),
                   graphType = "Heatmap",
                   width = 600, height = 400)

display(p)   # IJulia / Pluto / VS Code / Documenter
```

An exported `canvasXpress` alias is provided so R-style calls read the same in Julia.

## License

The Julia source in this repository is released under the [MIT License](LICENSE). The bundled
CanvasXpress JavaScript engine is distributed under its own CanvasXpress Community/Attribution
terms and retains its attribution mark.
