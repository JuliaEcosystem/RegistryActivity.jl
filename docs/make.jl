using Documenter, RegistryActivity

makedocs(
    modules = [RegistryActivity],
    sitename = "RegistryActivity.jl",
)

deploydocs(
    repo = "github.com/JuliaEcosystem/RegistryActivity.jl.git",
    devbranch = "main",
)
