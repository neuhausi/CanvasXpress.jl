using CanvasXpress
using Test

@testset "CanvasXpress scaffold" begin
    p = canvasxpress(; graphType="Heatmap", width=800, height=500)
    @test p isa CXPlot
    @test p.spec["config"]["graphType"] == "Heatmap"
    @test p.width == 800
    @test p.height == 500
    @test !isempty(p.id)

    # Two plots get distinct canvas ids.
    @test canvasxpress().id != canvasxpress().id

    # R-style alias resolves to the same constructor.
    @test CanvasXpress.canvasXpress === canvasxpress

    # data/config passthrough keeps explicit graphType.
    q = canvasxpress(; config=Dict("graphType" => "Bar"), graphType="Scatter2D")
    @test q.spec["config"]["graphType"] == "Bar"

    @test cxplot_version() isa String
end
