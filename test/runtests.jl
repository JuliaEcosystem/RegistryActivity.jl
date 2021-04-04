using RegistryActivity
using Test
using LibGit2
using Dates

origin = let
    general_path = RegistryActivity.find_general()
    try
        # If the local General registry is a git repository, use it...
        LibGit2.GitRepo(general_path)
        general_path
    catch e
        if e isa LibGit2.Error.GitError && e.code == LibGit2.Error.ENOTFOUND
            # ...otherwise clone directly from upstream
            "https://github.com/JuliaRegistries/General.git"
        else
            # If there are other issues, rethrow the error
            rethrow(e)
        end
    end
end

@testset "RegistryActivity" begin
    registry = RegistryActivity.clone_registry(; origin)

    m, p, v = registry_activity(registry;
                                start_month=Date(2019, 1),
                                end_month=Date(2019, 12),
                                filter=p->(occursin(r"_jll$", last(p)["name"])),
                                )
    @test m == Date(2019, 1):Month(1):Date(2019, 12)
    @test p == [0, 0, 0, 0, 0, 0, 0, 9, 58, 143, 176, 209]
    @test v == [0, 0, 0, 0, 0, 0, 0, 12, 98, 221, 274, 343]

    m, p, v = registry_activity(registry;
                                start_month=Date(2020, 1),
                                end_month=Date(2020, 12),
                                )
    @test m == Date(2020, 1):Month(1):Date(2020, 12)
    @test p == [2774, 2885, 3013, 3132, 3280, 3389, 3541, 3680, 3827, 3981, 4091, 4215]
    @test v == [13621, 15036, 16381, 17914, 19426, 20759, 22082, 23567, 24969, 26360, 27674, 29067]
end
