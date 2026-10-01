# Config-parameter catalog + validation.
#
# Ships the same `config-params.json` the R package uses (every CanvasXpress config
# parameter with its type, default, allowed values and description). It is the Julia
# equivalent of the JavaScript `.d.ts` / Python `CXConfig` typed surfaces: a searchable,
# documented reference for parameters that otherwise flow through keyword args unchecked.

const _CATALOG_PATH = normpath(joinpath(@__DIR__, "..", "data", "config-params.json"))

# Session cache of the parsed catalog (Vector of NamedTuples), loaded lazily.
const _CATALOG = Ref{Any}(nothing)
const _CATALOG_INDEX = Ref{Any}(nothing)

function _load_catalog()
    isfile(_CATALOG_PATH) ||
        error("CanvasXpress config catalog not found at $_CATALOG_PATH — reinstall the package.")
    raw = JSON3.read(read(_CATALOG_PATH, String))
    entries = NamedTuple[]
    index = Dict{String,Int}()
    for (i, e) in enumerate(raw.parameters)
        name = String(e.parameter)
        opts = haskey(e, :options) && e.options !== nothing ?
            Any[o for o in e.options] : nothing
        push!(entries, (
            parameter = name,
            type = haskey(e, :type) ? String(e.type) : "",
            default = haskey(e, :default) ? e.default : nothing,
            options = opts,
            description = haskey(e, :description) && e.description !== nothing ?
                String(e.description) : "",
        ))
        index[name] = i
    end
    return entries, index
end

"""
    cx_config_params() -> Vector{NamedTuple}

The CanvasXpress config-parameter catalog: one `NamedTuple` per parameter with fields
`parameter`, `type`, `default`, `options` (allowed values, or `nothing`) and
`description`. Memoized for the session.

```julia
params = cx_config_params()
first(p for p in params if p.parameter == "graphType")
filter(p -> occursin("legend", p.description), params)   # search descriptions
```
"""
function cx_config_params()
    if _CATALOG[] === nothing
        entries, index = _load_catalog()
        _CATALOG[] = entries
        _CATALOG_INDEX[] = index
    end
    return _CATALOG[]
end

function _catalog_index()
    cx_config_params()
    return _CATALOG_INDEX[]
end

# JS-ish type tokens a Julia value can satisfy (for the type-union check).
_value_type_tokens(::AbstractString) = ("string",)
_value_type_tokens(::Bool) = ("boolean",)
_value_type_tokens(::Integer) = ("integer", "number")
_value_type_tokens(::Real) = ("number",)
_value_type_tokens(::Union{AbstractVector,Tuple}) = ("array",)
_value_type_tokens(::Union{AbstractDict,NamedTuple}) = ("object",)
_value_type_tokens(::Any) = ()   # functions/JSCode/nothing/missing → skip type check

"""
    cx_validate_config(config; strict=false) -> NamedTuple

Check a config (an `AbstractDict`/`NamedTuple` of `name => value`) against the catalog.
Reports parameters that are not recognised, enumerated parameters set outside their
allowed `options`, and scalar values whose type is outside the parameter's declared
type union. Warns by default; `strict=true` throws instead. Returns
`(unknown, bad_options, bad_types)`.

Recognised-but-unlisted names (obfuscation aliases, or a parameter newer than the
installed catalog) are reported as unknown — a hint, not proof of error; `canvasxpress`
still accepts any parameter.
"""
function cx_validate_config(config; strict::Bool=false)
    params = cx_config_params()
    index = _catalog_index()

    pairs_ = config isa NamedTuple ? Base.pairs(config) : config
    supplied = Tuple{String,Any}[(string(k), v) for (k, v) in pairs_]

    unknown = String[]
    bad_options = Dict{String,Any}()
    bad_types = Dict{String,Any}()

    for (name, value) in supplied
        if !haskey(index, name)
            push!(unknown, name)
            continue
        end
        entry = params[index[name]]
        # enum check — only scalar strings, matching the R validator
        if entry.options !== nothing && value isa AbstractString && !(value in entry.options)
            bad_options[name] = value
        end
        # type-union check for scalars we can classify
        tokens = _value_type_tokens(value)
        if !isempty(tokens) && !isempty(entry.type)
            allowed = split(entry.type, '|')
            if !any(t -> t in allowed, tokens)
                bad_types[name] = value
            end
        end
    end

    if !isempty(unknown) || !isempty(bad_options) || !isempty(bad_types)
        msgs = String[]
        isempty(unknown) || push!(msgs, "Unknown parameter(s): " * join(unknown, ", "))
        for (name, value) in bad_options
            allowed = params[index[name]].options
            push!(msgs, "'$name' = '$value' is not an allowed value (options: " *
                        join(string.(allowed), ", ") * ")")
        end
        for (name, value) in bad_types
            push!(msgs, "'$name' = $(repr(value)) has type outside '" *
                        params[index[name]].type * "'")
        end
        text = join(msgs, "\n")
        strict ? error(text) : @warn text
    end

    return (unknown = unknown, bad_options = bad_options, bad_types = bad_types)
end
