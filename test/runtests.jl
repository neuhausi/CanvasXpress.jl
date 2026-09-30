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
        @test engine_version() == "70.6.0"
    end

    @testset "HTML snapshot (self-contained page, CDN)" begin
        p = canvasxpress(m1; vars=g, smps=s, graphType="Heatmap",
                         id="cx-test", width=640, height=480)
        page = cx_html_page(p; cdn=true, title="My Chart")

        # Page skeleton
        @test startswith(page, "<!doctype html>")
        @test occursin("<title>My Chart</title>", page)
        @test occursin("</html>", page)

        # Engine from cdnjs, pinned to the vendored version (js + css)
        @test occursin("cdnjs.cloudflare.com/ajax/libs/canvasXpress/70.6.0/canvasXpress.min.js", page)
        @test occursin("cdnjs.cloudflare.com/ajax/libs/canvasXpress/70.6.0/canvasXpress.css", page)

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

    @testset "inline without vendored engine errors clearly" begin
        # No engine is vendored in CI; cdn=false must raise, not silently break.
        @test_throws ErrorException cx_html_page(canvasxpress(m1); cdn=false)
    end

    @testset "show MIME methods" begin
        p = canvasxpress(m1; vars=g, smps=s, graphType="Heatmap", id="cx-show")

        use_cdn!(true)
        html = sprint(show, MIME("text/html"), p)
        use_cdn!(false)
        @test occursin("<canvas id=\"cx-show\"", html)
        @test occursin("new CanvasXpress({renderTo: \"cx-show\"", html)
        @test occursin("cdnjs.cloudflare.com/ajax/libs/canvasXpress/70.6.0", html)

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
end
