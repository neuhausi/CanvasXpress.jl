module CanvasXpress

using UUIDs
import JSON3
import Tables

export CXPlot, canvasxpress, canvasXpress, canvasxpress_json,
       cx_data_json, cx_json, cxplot_version,
       savehtml, browse, cx_html_page, JSCode, savefig,
       use_cdn!, reset_session!, engine_version,
       cx_config_params, cx_validate_config

# ---------------------------------------------------------------------------
# Type
# ---------------------------------------------------------------------------

"""
    CXPlot

A CanvasXpress chart specification plus render metadata.

Fields:
- `spec::Dict{String,Any}` — the `{data, config, events, afterRender}` object sent to the engine.
- `width` / `height` — requested canvas size in pixels.
- `id::String` — unique canvas id (`UUIDs.uuid4()`) so multiple cells never collide.
"""
struct CXPlot
    spec::Dict{String,Any}
    width::Int
    height::Int
    id::String
end

# ---------------------------------------------------------------------------
# Data-model construction (port of R setup_y / setup_x / setup_z)
# ---------------------------------------------------------------------------

# R uses a "V" prefix for BOTH missing row and column names
# (assignCanvasXpressRownames / assignCanvasXpressColnames). Preserve that.
_default_names(n::Integer) = String["V" * string(i) for i in 1:n]

_names_or_default(names, n::Integer) =
    names === nothing ? _default_names(n) : String[string(x) for x in names]

"""
    _y_from_matrix(m, vars, smps) -> Dict

Build the `y` data model from a matrix: rows are variables, columns are samples,
`data` is a row-major nested array (one inner array per variable).
"""
function _y_from_matrix(m::AbstractMatrix, vars, smps)
    nr, nc = size(m)
    v = _names_or_default(vars, nr)
    s = _names_or_default(smps, nc)
    length(v) == nr || throw(ArgumentError("vars length ($(length(v))) != matrix rows ($nr)"))
    length(s) == nc || throw(ArgumentError("smps length ($(length(s))) != matrix cols ($nc)"))
    data = Any[Any[m[i, j] for j in 1:nc] for i in 1:nr]
    return Dict{String,Any}("vars" => v, "smps" => s, "data" => data)
end

"""
    _y_from_table(tbl, rownames, smps) -> Dict

Build the `y` data model from a Tables.jl source. The `rownames` column holds the
variable ids (defaults to the first column); the remaining columns are the samples.
"""
function _y_from_table(tbl, rownames, smps)
    cols = Tables.columntable(tbl)
    colnames = collect(keys(cols))
    isempty(colnames) && throw(ArgumentError("table has no columns"))
    idcol = rownames === nothing ? first(colnames) : Symbol(rownames)
    idcol in colnames || throw(ArgumentError("rownames column $(idcol) not found in table"))
    smpcols = Symbol[c for c in colnames if c != idcol]
    vars = String[string(x) for x in cols[idcol]]
    s = smps === nothing ? String[string(c) for c in smpcols] : _names_or_default(smps, length(smpcols))
    nvars = length(vars)
    data = Any[Any[cols[smpcols[j]][i] for j in eachindex(smpcols)] for i in 1:nvars]
    return Dict{String,Any}("vars" => vars, "smps" => s, "data" => data)
end

# Turn an annotation source into the CanvasXpress x/z shape: an ordered mapping of
# annotation name => vector of values (one per sample/variable). `refids` are the
# y smps (for x) or y vars (for z); values must line up with them.
_annot_columns(::Nothing, refids, id, what) = nothing

function _annot_columns(annot::AbstractDict, refids, id, what)
    out = Dict{String,Any}()
    for (k, v) in annot
        vec = collect(v)
        length(vec) == length(refids) ||
            throw(ArgumentError("$what annotation \"$(k)\" has $(length(vec)) values, expected $(length(refids))"))
        out[string(k)] = vec
    end
    return out
end

function _annot_columns(annot, refids, id, what)
    if Tables.istable(annot)
        cols = Tables.columntable(annot)
        colnames = collect(keys(cols))
        if id !== nothing
            idsym = Symbol(id)
            idsym in colnames || throw(ArgumentError("id column $(idsym) not found in $what annotation"))
            ids = String[string(x) for x in cols[idsym]]
            ids == String[string(r) for r in refids] ||
                throw(ArgumentError("$what annotation id column does not match the data $(what == "smp" ? "samples" : "variables")"))
            colnames = Symbol[c for c in colnames if c != idsym]
        end
        out = Dict{String,Any}()
        for c in colnames
            vec = collect(cols[c])
            length(vec) == length(refids) ||
                throw(ArgumentError("$what annotation \"$(c)\" has $(length(vec)) values, expected $(length(refids))"))
            out[string(c)] = vec
        end
        return out
    end
    throw(ArgumentError("unsupported $what annotation type: $(typeof(annot))"))
end

# ---------------------------------------------------------------------------
# Public constructor
# ---------------------------------------------------------------------------

"""
    canvasxpress(data=nothing; graphType="Scatter2D", smpAnnot=nothing, varAnnot=nothing,
                 vars=nothing, smps=nothing, rownames=nothing,
                 smpAnnotId=nothing, varAnnotId=nothing,
                 events=nothing, afterRender=nothing,
                 width=600, height=400, validate=false, kwargs...) -> CXPlot

Construct a CanvasXpress chart. Mirrors the R `canvasXpress()` call shape.

`data` may be:
- an `AbstractMatrix` (rows = variables, columns = samples; name them with `vars`/`smps`),
- a Tables.jl source (the `rownames` column holds variable ids; other columns are samples),
- an `AbstractDict` holding a pre-built CanvasXpress data model (passed through untouched),
- `nothing` (config-only charts).

`smpAnnot` / `varAnnot` become the `x` / `z` annotation blocks and may be an
`AbstractDict` (name => per-sample/-variable values) or a Tables.jl source (pass the id
column via `smpAnnotId` / `varAnnotId`). Every remaining keyword becomes a config entry.
"""
function canvasxpress(data=nothing;
                      graphType="Scatter2D",
                      smpAnnot=nothing, varAnnot=nothing,
                      vars=nothing, smps=nothing, rownames=nothing,
                      smpAnnotId=nothing, varAnnotId=nothing,
                      events=nothing, afterRender=nothing,
                      width::Integer=600, height::Integer=400,
                      validate=false, id=nothing,
                      kwargs...)

    config = Dict{String,Any}("graphType" => string(graphType))
    for (k, v) in kwargs
        config[string(k)] = v
    end

    # validate=true warns on catalog issues; validate=:strict throws.
    if validate !== false
        cx_validate_config(config; strict=(validate === :strict))
    end

    local datamodel::Any
    if data === nothing
        datamodel = nothing
    elseif data isa AbstractDict
        # Pre-built CanvasXpress data model — pass through untouched.
        datamodel = data
    elseif data isa AbstractMatrix
        y = _y_from_matrix(data, vars, smps)
        datamodel = Dict{String,Any}(
            "y" => y,
            "x" => _annot_columns(smpAnnot, y["smps"], smpAnnotId, "smp"),
            "z" => _annot_columns(varAnnot, y["vars"], varAnnotId, "var"),
        )
    elseif Tables.istable(data)
        y = _y_from_table(data, rownames, smps)
        datamodel = Dict{String,Any}(
            "y" => y,
            "x" => _annot_columns(smpAnnot, y["smps"], smpAnnotId, "smp"),
            "z" => _annot_columns(varAnnot, y["vars"], varAnnotId, "var"),
        )
    else
        throw(ArgumentError("unsupported data type: $(typeof(data)); pass a matrix, a Tables.jl source, or a Dict"))
    end

    spec = Dict{String,Any}(
        "data" => datamodel,
        "config" => config,
        "events" => events,
        "afterRender" => afterRender,
    )
    canvasid = id === nothing ? "cx-" * string(uuid4()) : string(id)
    return CXPlot(spec, Int(width), Int(height), canvasid)
end

# API-shape alias so R code ports verbatim.
const canvasXpress = canvasxpress

"""
    canvasxpress_json(spec; width=600, height=400) -> CXPlot

Wrap a full CanvasXpress spec (an `AbstractDict`/`NamedTuple` with `data`/`config`, or a
JSON string) in a `CXPlot` without touching it.
"""
function canvasxpress_json(spec::AbstractDict; width::Integer=600, height::Integer=400)
    s = Dict{String,Any}(string(k) => v for (k, v) in spec)
    return CXPlot(s, Int(width), Int(height), "cx-" * string(uuid4()))
end

canvasxpress_json(spec::NamedTuple; kwargs...) =
    canvasxpress_json(Dict(string(k) => v for (k, v) in pairs(spec)); kwargs...)

function canvasxpress_json(spec::AbstractString; width::Integer=600, height::Integer=400)
    parsed = JSON3.read(spec, Dict{String,Any})
    return canvasxpress_json(parsed; width=width, height=height)
end

# ---------------------------------------------------------------------------
# JSON serialization (missing / NaN / Inf -> null)
# ---------------------------------------------------------------------------

_sanitize(::Missing) = nothing
_sanitize(::Nothing) = nothing
_sanitize(x::Symbol) = String(x)
_sanitize(x::AbstractString) = String(x)
_sanitize(x::Bool) = x
_sanitize(x::Integer) = x
_sanitize(x::AbstractFloat) = (isnan(x) || isinf(x)) ? nothing : x
_sanitize(x::AbstractDict) = Dict{String,Any}(string(k) => _sanitize(v) for (k, v) in x)
_sanitize(x::NamedTuple) = Dict{String,Any}(string(k) => _sanitize(v) for (k, v) in pairs(x))
_sanitize(x::Union{AbstractVector,Tuple}) = Any[_sanitize(e) for e in x]
_sanitize(x) = x

"""
    cx_json(p::CXPlot) -> String

Serialize the full `{data, config, events, afterRender}` spec to JSON, mapping
`missing`/`nothing`/`NaN`/`Inf` to `null`.
"""
cx_json(p::CXPlot) = JSON3.write(_sanitize(p.spec))

"""
    cx_data_json(p::CXPlot) -> String

Serialize just the `data` model (`y`/`x`/`z`) to JSON, mapping missing/NaN/Inf to `null`.
This matches the R `canvasXpress()` data model byte-for-byte for clean reference datasets.
"""
cx_data_json(p::CXPlot) = JSON3.write(_sanitize(p.spec["data"]))

"The CanvasXpress engine version this package vendors (set by the release build in P6)."
cxplot_version() = "70.7.0"

include("config.jl")
include("display.jl")
include("export.jl")

end # module
