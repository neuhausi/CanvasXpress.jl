module CanvasXpress

using UUIDs

export CXPlot, canvasxpress, canvasXpress, cxplot_version

"""
    CXPlot

A CanvasXpress chart specification plus render metadata.

Fields:
- `spec::Dict{String,Any}` — the `{data, config, events, afterRender}` spec sent to the engine.
- `width` / `height` — requested canvas size in pixels.
- `id::String` — unique canvas id (`UUIDs.uuid4()`) so multiple cells never collide.
"""
struct CXPlot
    spec::Dict{String,Any}
    width::Int
    height::Int
    id::String
end

"""
    canvasxpress(; graphType="Scatter2D", width=600, height=400, kwargs...) -> CXPlot

Construct a CanvasXpress chart. This P0 scaffold accepts a pre-built spec via the
`data`/`config` keywords and returns a `CXPlot`; the Tables/matrix data model
(`setup_y/x/z` port) and JSON serialization arrive in P1.
"""
function canvasxpress(; data=Dict{String,Any}(), config=Dict{String,Any}(),
                      graphType="Scatter2D", width::Integer=600, height::Integer=400)
    cfg = Dict{String,Any}(string(k) => v for (k, v) in pairs(config))
    haskey(cfg, "graphType") || (cfg["graphType"] = graphType)
    spec = Dict{String,Any}(
        "data" => Dict{String,Any}(string(k) => v for (k, v) in pairs(data)),
        "config" => cfg,
    )
    return CXPlot(spec, Int(width), Int(height), string(uuid4()))
end

# API-shape alias so R code ports verbatim (see package docs). The core
# implementation lands in P1; this scaffold establishes the type and surface.
const canvasXpress = canvasxpress

"The CanvasXpress engine version this package vendors (set by the release build in P6)."
cxplot_version() = "unreleased"

end # module
