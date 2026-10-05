using CanvasXpress
using Test
import JSON3

const FIXTURES = joinpath(@__DIR__, "fixtures")

# Parse two JSON strings to a canonical structure and compare (order-insensitive
# for object keys). This is the meaningful "equals R output" check.
canon(s::AbstractString) = JSON3.read(s, Any)
equal_json(a::AbstractString, b::AbstractString) = canon(a) == canon(b)

fixture(name) = read(joinpath(FIXTURES, name * ".json"), String)

@testset "CanvasXpress.jl" begin

    @testset "scaffold surface" begin
        p = canvasxpress(; graphType="Heatmap", width=800, height=500)
        @test p isa CXPlot
        @test p.spec["config"]["graphType"] == "Heatmap"
        @test p.width == 800 && p.height == 500
        @test !isempty(p.id)
        @test canvasxpress().id != canvasxpress().id
        @test CanvasXpress.canvasXpress === canvasxpress
    end

    @testset "config kwargs" begin
        p = canvasxpress([1 2; 3 4]; graphType="Bar", colorBy="Treatment", title="X")
        @test p.spec["config"]["graphType"] == "Bar"
        @test p.spec["config"]["colorBy"] == "Treatment"
        @test p.spec["config"]["title"] == "X"
    end

    # ---- P1 gate: round-trip JSON equals R canvasXpress() for 5 datasets ----

    m1 = [1 2 3 4; 5 6 7 8; 9 10 11 12]
    g = ["g1", "g2", "g3"]
    s = ["s1", "s2", "s3", "s4"]

    @testset "matrix_basic" begin
        p = canvasxpress(m1; vars=g, smps=s, graphType="Heatmap")
        @test equal_json(cx_data_json(p), fixture("matrix_basic"))
    end

    @testset "matrix_nodimnames" begin
        m2 = [1.5 2.5 3.5; 4.5 5.5 6.5]
        p = canvasxpress(m2; graphType="Heatmap")
        @test equal_json(cx_data_json(p), fixture("matrix_nodimnames"))
    end

    @testset "smpannot_numeric" begin
        smp = Dict("Dose" => [5, 10, 15, 20], "Age" => [30, 40, 50, 60])
        p = canvasxpress(m1; vars=g, smps=s, smpAnnot=smp, graphType="Heatmap")
        @test equal_json(cx_data_json(p), fixture("smpannot_numeric"))
    end

    @testset "varannot_char" begin
        var = Dict("Pathway" => ["P1", "P2", "P1"], "Class" => ["A", "B", "A"])
        p = canvasxpress(m1; vars=g, smps=s, varAnnot=var, graphType="Heatmap")
        @test equal_json(cx_data_json(p), fixture("varannot_char"))
    end

    @testset "matrix_missing" begin
        m5 = Matrix{Any}(copy(m1))
        m5[1, 2] = missing
        m5[3, 4] = NaN
        smp = Dict("Dose" => [5, 10, 15, 20], "Age" => [30, 40, 50, 60])
        var = Dict("Pathway" => ["P1", "P2", "P1"], "Class" => ["A", "B", "A"])
        p = canvasxpress(m5; vars=g, smps=s, smpAnnot=smp, varAnnot=var, graphType="Heatmap")
        @test equal_json(cx_data_json(p), fixture("matrix_missing"))
    end

    # ---- data-layer behaviors ----

    @testset "Tables.jl source" begin
        # Column table: id column `gene` -> vars; other columns -> samples.
        tbl = (gene=["g1", "g2"], s1=[1, 3], s2=[2, 4])
        p = canvasxpress(tbl; rownames=:gene, graphType="Heatmap")
        y = p.spec["data"]["y"]
        @test y["vars"] == ["g1", "g2"]
        @test y["smps"] == ["s1", "s2"]
        @test y["data"] == Any[Any[1, 2], Any[3, 4]]
    end

    @testset "Dict passthrough" begin
        raw = Dict("y" => Dict("vars" => ["a"], "smps" => ["b"], "data" => [[1]]))
        p = canvasxpress(raw; graphType="Scatter2D")
        @test p.spec["data"] === raw
    end

    @testset "JSON null mapping" begin
        j = cx_json(canvasxpress([1.0 NaN; Inf 4.0]; graphType="Heatmap"))
        parsed = JSON3.read(j, Any)
        d = parsed["data"]["y"]["data"]
        @test d[1][2] === nothing   # NaN -> null
        @test d[2][1] === nothing   # Inf -> null
        @test parsed["data"]["x"] === nothing
    end

    @testset "annotation length mismatch errors" begin
        @test_throws ArgumentError canvasxpress(m1; vars=g, smps=s,
            smpAnnot=Dict("Dose" => [1, 2]), graphType="Heatmap")
    end

    @testset "canvasxpress_json" begin
        p = canvasxpress_json("""{"data":{"y":{"vars":["a"]}},"config":{"graphType":"Bar"}}""")
        @test p.spec["config"]["graphType"] == "Bar"
        @test p.spec["data"]["y"]["vars"] == ["a"]
    end

    # ---- P2: display / HTML emission ----

    @testset "fixed id + engine version" begin
        @test canvasxpress(m1; id="cx-test").id == "cx-test"
        # 3-part semver, set by the release build; don't pin an exact value.
        @test occursin(r"^\d+\.\d+\.\d+$", engine_version())
    end

    @testset "HTML snapshot (self-contained page, CDN)" begin
        p = canvasxpress(m1; vars=g, smps=s, graphType="Heatmap",
                         id="cx-test", width=640, height=480)
        page = cx_html_page(p; cdn=true, title="My Chart")

        # Page skeleton
        @test startswith(page, "<!doctype html>")
        @test occursin("<title>My Chart</title>", page)
        @test occursin("</html>", page)

        # Engine from cdnjs, pinned to the current engine version (js + css)
        @test occursin("cdnjs.cloudflare.com/ajax/libs/canvasXpress/$(engine_version())/canvasXpress.min.js", page)
        @test occursin("cdnjs.cloudflare.com/ajax/libs/canvasXpress/$(engine_version())/canvasXpress.css", page)

        # Sized wrapper (canvas shrink-wraps its parent) + canvas id
        @test occursin("width:640px; height:480px;", page)
        @test occursin("<canvas id=\"cx-test\" width=\"640\" height=\"480\">", page)

        # Pluto/re-run safety: destroy prior instance on this target, then construct
        @test occursin("CanvasXpress.destroy", page)
        @test occursin("new CanvasXpress({renderTo: \"cx-test\"", page)

        # Embedded data model equals the R reference
        mdata = match(r"data: (.*?), config: "s, page)
        @test mdata !== nothing
        @test equal_json(String(mdata.captures[1]), fixture("matrix_basic"))
    end

    @testset "savehtml writes the page" begin
        p = canvasxpress(m1; id="cx-test")
        path = tempname() * ".html"
        savehtml(p, path; cdn=true)
        @test isfile(path)
        @test read(path, String) == cx_html_page(p; cdn=true)
        rm(path)
    end

    @testset "offline engine via set_engine_dir!" begin
        # No local engine by default -> cdn=false must raise, not silently break.
        @test_throws ErrorException cx_html_page(canvasxpress(m1); cdn=false)
        # Point at a local engine -> cdn=false inlines it; then revert to the CDN.
        dir = mktempdir()
        write(joinpath(dir, "canvasXpress.min.js"), "/* fake engine */")
        write(joinpath(dir, "canvasXpress.css"), "/* fake css */")
        set_engine_dir!(dir)
        @test occursin("fake engine", cx_html_page(canvasxpress(m1); cdn=false))
        set_engine_dir!(nothing)
        rm(dir; recursive=true)
    end

    @testset "show MIME methods" begin
        p = canvasxpress(m1; vars=g, smps=s, graphType="Heatmap", id="cx-show")

        html = sprint(show, MIME("text/html"), p)
        @test occursin("<canvas id=\"cx-show\"", html)
        @test occursin("new CanvasXpress({renderTo: \"cx-show\"", html)
        @test occursin("cdnjs.cloudflare.com/ajax/libs/canvasXpress/$(engine_version())", html)

        json = sprint(show, MIME("application/canvasxpress+json"), p)
        @test json == cx_json(p)

        @test showable(MIME("text/html"), p)
        @test showable(MIME("application/canvasxpress+json"), p)
    end

    @testset "JSCode events emitted raw" begin
        cb = JSCode("function(o,e,t){ return o; }")
        p = canvasxpress(m1; id="cx-ev", events=cb)
        page = cx_html_page(p; cdn=true)
        @test occursin("events: function(o,e,t){ return o; }", page)
        @test !occursin("\"function(o,e,t)", page)  # not quoted as a string
    end

    # ---- P3: config catalog + validation ----

    @testset "catalog count == schema count" begin
        params = cx_config_params()
        # The vendored catalog's declared count is the schema property count.
        declared = JSON3.read(read(joinpath(@__DIR__, "..", "data", "config-params.json"), String)).count
        @test length(params) == declared
        @test length(params) > 1000
        # memoized (same object each call)
        @test cx_config_params() === params
    end

    @testset "catalog lookup shape" begin
        params = cx_config_params()
        gt = only(filter(p -> p.parameter == "graphType", params))
        @test gt.type == "string|boolean"
        @test "Bar" in gt.options
        @test gt.description isa String
        # non-enumerated parameter has no options
        cb = only(filter(p -> p.parameter == "colorBy", params))
        @test cb.options === nothing
    end

    @testset "validate: unknown key warns" begin
        r = @test_logs (:warn,) cx_validate_config(Dict("notARealParam" => 1))
        @test "notARealParam" in r.unknown
    end

    @testset "validate: bad enum warns" begin
        r = @test_logs (:warn,) cx_validate_config(Dict("align" => "sideways"))
        @test haskey(r.bad_options, "align")
    end

    @testset "validate: bad type warns" begin
        # adjustBezier is boolean-only; a string is the wrong type.
        r = @test_logs (:warn,) cx_validate_config(Dict("adjustBezier" => "yes"))
        @test haskey(r.bad_types, "adjustBezier")
    end

    @testset "validate: clean config is silent" begin
        r = @test_nowarn cx_validate_config(Dict("align" => "center", "colorBy" => "Grp"))
        @test isempty(r.unknown) && isempty(r.bad_options) && isempty(r.bad_types)
    end

    @testset "validate: strict throws" begin
        @test_throws ErrorException cx_validate_config(Dict("bogus" => 1); strict=true)
    end

    @testset "validate via canvasxpress kwarg" begin
        @test_logs (:warn,) canvasxpress(m1; vars=g, smps=s,
            graphType="Bar", bogusParam=1, validate=true)
        @test_throws ErrorException canvasxpress(m1; vars=g, smps=s,
            graphType="Bar", bogusParam=1, validate=:strict)
        # validate=false (default) never touches the catalog
        @test_nowarn canvasxpress(m1; vars=g, smps=s, bogusParam=1)
    end

    # ---- P4: static export (savefig via cxplot) ----

    @testset "savefig spec is {data, config}" begin
        p = canvasxpress(m1; vars=g, smps=s, graphType="Heatmap")
        sp = CanvasXpress._savefig_spec(p)
        @test haskey(sp, "data") && haskey(sp, "config")
        @test sp["config"]["graphType"] == "Heatmap"
        @test equal_json(JSON3.write(sp["data"]), fixture("matrix_basic"))
        # afterRender carried through as raw JS
        sp2 = CanvasXpress._savefig_spec(canvasxpress(m1; afterRender=JSCode("draw()")))
        @test sp2["afterRender"] == "draw()"
    end

    @testset "savefig command construction" begin
        p = canvasxpress(m1; id="cx", width=500, height=400)
        a = CanvasXpress._savefig_args(p, "out.png"; width=500, height=400, specfile="S.json")
        @test a[1] == "render" && a[2] == "S.json"
        @test "-o" in a
        @test occursin("out.png", join(a, " "))
        wi = findfirst(==("--width"), a)
        @test a[wi+1] == "500"
        # local engine -> --engine-path; otherwise pin --engine <ver> (default: CDN)
        if CanvasXpress._engine_local()
            @test "--engine-path" in a
        else
            @test "--engine" in a && engine_version() in a
        end
    end

    @testset "savefig rejects non-PNG" begin
        p = canvasxpress(m1)
        @test_throws ErrorException savefig(p, "chart.svg")
        @test_throws ErrorException savefig(p, "chart.pdf")
    end

    @testset "clear error when cxplot absent" begin
        msg = CanvasXpress._cxplot_missing_msg()
        @test occursin("npm i -g cxplot", msg)
        @test occursin("Docker", msg)
    end

    @testset "savefig surfaces a failed render" begin
        # `true` exits 0 but writes nothing -> savefig must not claim success.
        p = canvasxpress(m1)
        out = tempname() * ".png"
        @test_throws ErrorException savefig(p, out; runner=["true"])
        @test !isfile(out)
    end

    # ---- extra coverage ----

    @testset "canvasxpress_json variants" begin
        nt = canvasxpress_json((data=Dict("y" => Dict("vars" => ["a"])),
                                config=Dict("graphType" => "Line")))
        @test nt.spec["config"]["graphType"] == "Line"
        d = canvasxpress_json(Dict("data" => Dict(), "config" => Dict("graphType" => "Pie")))
        @test d.spec["config"]["graphType"] == "Pie"
        @test startswith(d.id, "cx-")
    end

    @testset "config-only + Tables smps override" begin
        p = canvasxpress(; graphType="Map")
        @test p.spec["data"] === nothing
        @test cx_json(p) isa String
        tbl = (gene=["g1", "g2"], a=[1, 2], b=[3, 4])
        q = canvasxpress(tbl; rownames=:gene, smps=["x", "y"], graphType="Heatmap")
        @test q.spec["data"]["y"]["smps"] == ["x", "y"]
    end

    @testset "validate :strict via canvasxpress returns, varAnnot errors" begin
        @test_throws ArgumentError canvasxpress(m1; vars=g, smps=s,
            varAnnot=Dict("Bad" => ["only-one"]), graphType="Heatmap")
    end

    @testset "download_engine! (network)" begin
        try
            dir = download_engine!()
            @test isfile(joinpath(dir, "canvasXpress.min.js"))
            @test CanvasXpress._engine_local()
            # a second call reuses the cache (no error)
            @test download_engine!() == dir
            set_engine_dir!(nothing)
        catch e
            @warn "download_engine! skipped (no network?)" exception = e
        end
    end
end
