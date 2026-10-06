# Display / HTML emission for CXPlot.
#
# Engine delivery: by default the CanvasXpress engine (JS + CSS) is loaded from cdnjs,
# pinned to `engine_version()`. For offline use, point `set_engine_dir!` at a directory
# holding `canvasXpress.min.js` (and `canvasXpress.css`) and it is inlined instead.

# ---- engine delivery state ----

const ENGINE_VERSION = Ref("71.0.0")                 # cdnjs version this package pins to
const _ENGINE_DIR = Ref{Union{Nothing,String}}(nothing)  # local engine dir (offline), or CDN
const _INJECTED = Ref(false)                          # local engine already inlined this session?

"""
    engine_version() -> String

The CanvasXpress engine version this package loads (from cdnjs, or a matching local build).
"""
engine_version() = ENGINE_VERSION[]

"""
    set_engine_dir!(dir)

Use a local CanvasXpress engine for offline rendering: `dir` must contain
`canvasXpress.min.js` (and ideally `canvasXpress.css`), which are then inlined into the
HTML instead of loaded from cdnjs. Pass `nothing` to go back to the CDN.
"""
function set_engine_dir!(dir::Union{Nothing,AbstractString})
    if dir !== nothing && !isfile(joinpath(dir, "canvasXpress.min.js"))
        throw(ArgumentError("no canvasXpress.min.js in $(dir)"))
    end
    _ENGINE_DIR[] = dir === nothing ? nothing : String(dir)
    _INJECTED[] = false
    return _ENGINE_DIR[]
end

"""
    download_engine!(; version=engine_version(), force=false) -> String

Download the pinned CanvasXpress engine (`canvasXpress.min.js` + `canvasXpress.css`) from
cdnjs into a persistent per-version cache, then switch to it via [`set_engine_dir!`] for
offline rendering. The download happens once per version (reused on later calls); pass
`force=true` to re-download. Returns the cache directory. Requires network on first use.
"""
function download_engine!(; version::AbstractString=engine_version(), force::Bool=false)
    dir = joinpath(Scratch.get_scratch!(@__MODULE__, "engine"), version)
    isdir(dir) || mkpath(dir)
    base = "https://cdnjs.cloudflare.com/ajax/libs/canvasXpress/$(version)"
    for f in ("canvasXpress.min.js", "canvasXpress.css")
        dst = joinpath(dir, f)
        (force || !isfile(dst)) && Downloads.download("$(base)/$(f)", dst)
    end
    set_engine_dir!(dir)
    return dir
end

_engine_js_path() = _ENGINE_DIR[] === nothing ? nothing : joinpath(_ENGINE_DIR[], "canvasXpress.min.js")
_engine_css_path() = _ENGINE_DIR[] === nothing ? nothing : joinpath(_ENGINE_DIR[], "canvasXpress.css")
_engine_local() = _ENGINE_DIR[] !== nothing

_cdn_js() = "https://cdnjs.cloudflare.com/ajax/libs/canvasXpress/$(ENGINE_VERSION[])/canvasXpress.min.js"
_cdn_css() = "https://cdnjs.cloudflare.com/ajax/libs/canvasXpress/$(ENGINE_VERSION[])/canvasXpress.css"

# Keep an embedded blob from prematurely closing the surrounding <script>/<style>.
_script_safe(s::AbstractString) = replace(s, "</" => "<\\/")

# ---- JS literals for events / afterRender (raw JS, not JSON) ----

"""
    JSCode(code::String)

Marks a string as raw JavaScript (for `events` / `afterRender`), emitted verbatim
instead of being quoted — the same idea as R's `htmlwidgets::JS`.
"""
struct JSCode
    code::String
end

_js_literal(::Nothing) = "null"
_js_literal(j::JSCode) = j.code
_js_literal(s::AbstractString) = s   # event/afterRender strings are inherently JS

# ---- engine delivery blocks ----

function _engine_inline()
    io = IOBuffer()
    css = _engine_css_path()
    if css !== nothing && isfile(css)
        println(io, "<style>", _script_safe(read(css, String)), "</style>")
    end
    println(io, "<script>", _script_safe(read(_engine_js_path(), String)), "</script>")
    return String(take!(io))
end

_engine_cdn() = string(
    "<link rel=\"stylesheet\" href=\"", _cdn_css(), "\">\n",
    "<script src=\"", _cdn_js(), "\"></script>")

# Runtime-guarded CDN loader for notebook cells (append once, render when ready).
_engine_cdn_loader() = string(
    "if(!window.CanvasXpress&&!window.__cxLoading){window.__cxLoading=true;",
    "var _l=document.createElement('link');_l.rel='stylesheet';_l.href='", _cdn_css(), "';document.head.appendChild(_l);",
    "var _s=document.createElement('script');_s.src='", _cdn_js(), "';document.head.appendChild(_s);}")

# ---- render script (destroy prior instance on target, then construct) ----

function _render_script(p::CXPlot; loader::AbstractString="")
    data = _script_safe(JSON3.write(_sanitize(p.spec["data"])))
    config = _script_safe(JSON3.write(_sanitize(p.spec["config"])))
    events = _js_literal(get(p.spec, "events", nothing))
    after = _js_literal(get(p.spec, "afterRender", nothing))
    id = p.id
    return """
    <script>
    (function(){
      $loader
      function render(){
        try {
          for (var i = 0; i < CanvasXpress.instances.length; i++) {
            if (CanvasXpress.instances[i].target && CanvasXpress.instances[i].target.match("$id")) {
              CanvasXpress.destroy(CanvasXpress.instances[i].target);
            }
          }
        } catch (e) {}
        new CanvasXpress({renderTo: "$id", data: $data, config: $config, events: $events, afterRender: $after, width: $(p.width), height: $(p.height)});
      }
      function ready(){ if (window.CanvasXpress) { render(); } else { setTimeout(ready, 30); } }
      ready();
    })();
    </script>"""
end

# Inner wrapper sized to the requested dimensions — the CX canvas shrink-wraps its
# direct parent, so it must have an explicitly sized wrapper.
_wrapper(p::CXPlot) = string(
    "<div style=\"width:", p.width, "px; height:", p.height, "px;\">",
    "<canvas id=\"", p.id, "\" width=\"", p.width, "\" height=\"", p.height, "\"></canvas></div>")

# ---- notebook display ----

function Base.show(io::IO, ::MIME"text/html", p::CXPlot)
    print(io, _wrapper(p), "\n")
    if _engine_local()
        # Offline: inline the local engine once per session, then just render.
        if !_INJECTED[]
            print(io, _engine_inline(), "\n")
            _INJECTED[] = true
        end
        print(io, _render_script(p))
    else
        # CDN: append the loader once at runtime (inside the render IIFE).
        print(io, _render_script(p; loader=_engine_cdn_loader()))
    end
end

# VS Code / Jupyter renderers that understand the CanvasXpress mime get the raw spec.
Base.show(io::IO, ::MIME"application/canvasxpress+json", p::CXPlot) =
    print(io, cx_json(p))

Base.showable(::MIME"text/html", ::CXPlot) = true
Base.showable(::MIME"application/canvasxpress+json", ::CXPlot) = true

# ---- self-contained page ----

"""
    cx_html_page(p; cdn=!offline, title="") -> String

Return a stand-alone HTML page. The engine is loaded from cdnjs when `cdn=true`; when
`cdn=false` it is inlined from the directory set via [`set_engine_dir!`](@ref) (an error
if none is set). The default follows whichever engine source is currently configured.
"""
function cx_html_page(p::CXPlot; cdn::Bool=!_engine_local(), title::AbstractString="")
    local head::String
    if cdn
        head = _engine_cdn()
    elseif _engine_local()
        head = _engine_inline()
    else
        error("cdn=false needs a local engine; call set_engine_dir!(dir) first, or pass cdn=true.")
    end
    return string(
        "<!doctype html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n",
        "<title>", title, "</title>\n", head, "\n</head>\n<body>\n",
        _wrapper(p), "\n", _render_script(p), "\n</body>\n</html>\n")
end

"""
    savehtml(p, path; cdn=!offline, title="")

Write a self-contained HTML page for `p` to `path`.
"""
function savehtml(p::CXPlot, path::AbstractString; cdn::Bool=!_engine_local(), title::AbstractString="")
    open(path, "w") do io
        write(io, cx_html_page(p; cdn=cdn, title=title))
    end
    return path
end

"""
    browse(p; cdn=!offline)

Write `p` to a temporary HTML file and open it in the default browser.
"""
function browse(p::CXPlot; cdn::Bool=!_engine_local())
    path = tempname() * ".html"
    savehtml(p, path; cdn=cdn)
    cmd = Sys.isapple() ? `open $path` :
          Sys.iswindows() ? `cmd /c start "" $path` : `xdg-open $path`
    try
        run(cmd)
    catch e
        @warn "could not open a browser automatically; open the file manually" path exception = e
    end
    return path
end
