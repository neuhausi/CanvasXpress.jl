# Static export via the `cxplot` CLI (or its container).
#
# cxplot renders a `{data, config}` figure with the SAME engine the browser runs,
# headless via Playwright/Chromium. Output is PNG only (no SVG/PDF). By default savefig
# pins `--engine <engine_version()>` (cdnjs, cached); set a local engine with
# `set_engine_dir!` (or pass `engine_path`) to render against a specific build.

# The figure spec cxplot accepts: {data, config} (+ optional afterRender replay).
function _savefig_spec(p::CXPlot)
    spec = Dict{String,Any}(
        "data" => _sanitize(p.spec["data"]),
        "config" => _sanitize(p.spec["config"]),
    )
    af = get(p.spec, "afterRender", nothing)
    if af isa JSCode
        spec["afterRender"] = af.code
    elseif af isa AbstractString
        spec["afterRender"] = af
    end
    return spec
end

_cxplot_missing_msg() = string(
    "cxplot not found. Install it with `npm i -g cxplot` (then `npx playwright install ",
    "chromium`), or install Docker to use `ghcr.io/neuhausi/cxplot`. ",
    "Pass runner=[\"cxplot\"] (or a full command) to point at a specific install.")

# Resolve the command that runs cxplot: an explicit runner, then `cxplot` on PATH,
# then Docker; otherwise a clear error naming both install routes.
function _resolve_cxplot(runner, engine)
    runner !== nothing && return collect(String, runner)
    Sys.which("cxplot") !== nothing && return String["cxplot"]
    if Sys.which("docker") !== nothing
        img = "ghcr.io/neuhausi/cxplot:" * something(engine, engine_version())
        return String["docker", "run", "--rm", "__DOCKER__", img]  # __DOCKER__ = volume placeholder
    end
    error(_cxplot_missing_msg())
end

# Build the cxplot `render` arguments (everything after the command base). Split out
# so it can be unit-tested without executing cxplot.
function _savefig_args(p::CXPlot, path::AbstractString;
                       width::Integer, height::Integer,
                       engine=nothing, engine_path=nothing, timeout=nothing,
                       specfile::AbstractString="SPEC.json")
    args = String["render", specfile, "-o", abspath(path),
                  "--width", string(width), "--height", string(height)]
    if engine_path !== nothing
        append!(args, ["--engine-path", string(engine_path)])
    elseif _engine_local()
        append!(args, ["--engine-path", _engine_js_path()])
    elseif engine !== nothing
        append!(args, ["--engine", string(engine)])
    else
        append!(args, ["--engine", engine_version()])
    end
    timeout !== nothing && append!(args, ["--timeout", string(timeout)])
    return args
end

"""
    savefig(p, path; width=p.width, height=p.height, engine=nothing,
            engine_path=nothing, timeout=nothing, runner=nothing) -> path

Render `p` to a PNG at `path` using the `cxplot` CLI (or the `ghcr.io/neuhausi/cxplot`
container as a fallback). cxplot renders **PNG only** — an SVG/PDF path is rejected.

By default it pins `--engine engine_version()` (cdnjs); if a local engine is configured via
`set_engine_dir!` (or `engine_path` is passed) that build is used instead so the PNG matches
the interactive render. Pass `runner` (e.g. `["npx", "cxplot"]`) to choose how cxplot is
invoked. Errors clearly if neither cxplot nor Docker is available.
"""
function savefig(p::CXPlot, path::AbstractString;
                 width::Integer=p.width, height::Integer=p.height,
                 engine=nothing, engine_path=nothing, timeout=nothing, runner=nothing)
    endswith(lowercase(path), ".png") ||
        error("cxplot renders PNG only; got \"$path\". Use a .png output path " *
              "(SVG/PDF are not supported).")
    path = abspath(path)
    base = _resolve_cxplot(runner, engine)
    specjson = JSON3.write(_savefig_spec(p))

    if runner === nothing && !isempty(base) && base[1] == "docker"
        # Docker: mount the output directory and reference files inside the container.
        outdir = dirname(path)
        specfile = joinpath(outdir, "._cxplot_spec.json")
        write(specfile, specjson)
        img = base[end]
        cmd = String["docker", "run", "--rm", "-v", "$outdir:/work", img,
                     "render", "/work/" * basename(specfile),
                     "-o", "/work/" * basename(path),
                     "--width", string(width), "--height", string(height)]
        engine !== nothing && append!(cmd, ["--engine", string(engine)])
        timeout !== nothing && append!(cmd, ["--timeout", string(timeout)])
        try
            run(Cmd(cmd))
        finally
            rm(specfile; force=true)
        end
    else
        tmp = tempname() * ".json"
        write(tmp, specjson)
        args = _savefig_args(p, path; width=width, height=height, engine=engine,
                             engine_path=engine_path, timeout=timeout, specfile=tmp)
        try
            run(Cmd(vcat(base, args)))
        finally
            rm(tmp; force=true)
        end
    end

    isfile(path) || error("cxplot ran but did not produce $path")
    return path
end
