# Display / HTML emission for CXPlot.
#
# Engine delivery (decision D2): default = inline the vendored min.js once per
# notebook session; `use_cdn!(true)` switches to cdnjs pinned to the vendored
# version. The vendored files are copied into data/ by the release build (P6); when
# they are absent, inline requests fall back to the CDN with a one-time warning.

# ---- session / engine state ----

const ENGINE_VERSION = Ref("70.6.0")   # updated by the P6 release build
const _USE_CDN = Ref(false)            # default: inline (D2)
const _INJECTED = Ref(false)           # engine already inlined this session?
const _WARNED_NO_ENGINE = Ref(false)

"""
    use_cdn!(flag=true)

Deliver the engine from cdnjs (pinned to `engine_version()`) instead of inlining the
vendored `min.js`. Good for small, online notebooks.
"""
use_cdn!(flag::Bool=true) = (_USE_CDN[] = flag; nothing)

"""
    reset_session!()

Forget that the engine was inlined this session, so the next `display` re-inlines it
(use after clearing a notebook's outputs).
"""
reset_session!() = (_INJECTED[] = false; nothing)

"The CanvasXpress engine version this package delivers (vendored or via CDN)."
engine_version() = ENGINE_VERSION[]

_engine_js_path() = normpath(joinpath(@__DIR__, "..", "data", "canvasXpress.min.js"))
_engine_css_path() = normpath(joinpath(@__DIR__, "..", "data", "canvasXpress.css"))
_engine_vendored() = isfile(_engine_js_path()) && isfile(_engine_css_path())

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

# ---- engine injection blocks ----

function _engine_inline()
    io = IOBuffer()
    println(io, "<style>", _script_safe(read(_engine_css_path(), String)), "</style>")
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
    if _USE_CDN[]
        # CDN: append loader once at runtime (inside the render IIFE).
        print(io, _render_script(p; loader=_engine_cdn_loader()))
    else
        if _engine_vendored()
            if !_INJECTED[]
                print(io, _engine_inline(), "\n")
                _INJECTED[] = true
            end
            print(io, _render_script(p))
        else
            if !_WARNED_NO_ENGINE[]
                @warn "vendored engine not found ($(_engine_js_path())); using the CDN. Call use_cdn!() to silence this, or install a release build that vendors the engine (P6)."
                _WARNED_NO_ENGINE[] = true
            end
            print(io, _render_script(p; loader=_engine_cdn_loader()))
        end
    end
end

# VS Code / Jupyter renderers that understand the CanvasXpress mime get the raw spec.
Base.show(io::IO, ::MIME"application/canvasxpress+json", p::CXPlot) =
    print(io, cx_json(p))

Base.showable(::MIME"text/html", ::CXPlot) = true
Base.showable(::MIME"application/canvasxpress+json", ::CXPlot) = true

# ---- self-contained page ----

"""
    cx_html_page(p; cdn=false, title="") -> String

Return a stand-alone HTML page (`cxHtmlPage` equivalent). With `cdn=false` the engine
is inlined from the vendored files (errors if they are absent); `cdn=true` links cdnjs.
"""
function cx_html_page(p::CXPlot; cdn::Bool=false, title::AbstractString="")
    local head::String
    if cdn
        head = _engine_cdn()
    elseif _engine_vendored()
        head = _engine_inline()
    else
        error("no vendored engine found at $(_engine_js_path()). Pass cdn=true, or use a " *
              "release build that vendors the engine (P6).")
    end
    return string(
        "<!doctype html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n",
        "<title>", title, "</title>\n", head, "\n</head>\n<body>\n",
        _wrapper(p), "\n", _render_script(p), "\n</body>\n</html>\n")
end

"""
    savehtml(p, path; cdn=false, title="")

Write a self-contained HTML page for `p` to `path`.
"""
function savehtml(p::CXPlot, path::AbstractString; cdn::Bool=false, title::AbstractString="")
    open(path, "w") do io
        write(io, cx_html_page(p; cdn=cdn, title=title))
    end
    return path
end

"""
    browse(p; cdn=false)

Write `p` to a temporary HTML file and open it in the default browser.
"""
function browse(p::CXPlot; cdn::Bool=(!_engine_vendored()))
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
