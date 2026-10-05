using Documenter
using CanvasXpress

makedocs(
    sitename = "CanvasXpress.jl",
    modules = [CanvasXpress],
    authors = "Isaac Neuhaus and contributors",
    pages = ["Home" => "index.md"],
    checkdocs = :exports,
    format = Documenter.HTML(; canonical = "https://neuhausi.github.io/CanvasXpress.jl"),
)

deploydocs(
    repo = "github.com/neuhausi/CanvasXpress.jl.git",
    devbranch = "main",
    push_preview = false,
)
