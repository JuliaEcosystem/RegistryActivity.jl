module RegistryActivity

# Note about the statistics of the General registry: about 15k versions and 600
# packages were removed in October 2019 with
# https://github.com/JuliaRegistries/General/pull/4169.  It's complicated to
# deal with this because some packages had only some versions removed, others
# got completely removed and then they came back into the registry later.

using Pkg, Dates, LibGit2, TOML

export registry_activity

"""
    general_registry() -> String

Guess the path of the General registry.
"""
general_registry() =
    first(joinpath(d, "registries", "General") for d in Pkg.depots() if isfile(joinpath(d, "registries", "General", "Registry.toml")))

"""
    clone_registry(; origin="https://github.com/JuliaRegistries/General.git", dest=mktempdir())

Do a git clone of `origin` to `dest`.
"""
function clone_registry(;
                        origin="https://github.com/JuliaRegistries/General.git",
                        dest=mktempdir(),
                        )
    LibGit2.clone(origin, dest)
    return dest
end

"""
    get_date(c)

Get the UTC date of the Git commit `c`.
"""
function get_date(c)
    committer = LibGit2.committer(c)
    return Date(unix2datetime(committer.time + 60 * committer.time_offset))
end

"""
    extrema_dates(path)

Get the first and last date of commits in the git repository at `path`.
"""
function extrema_dates(path)
    repo = GitRepo(path)
    # Find the dates of all commits in the repo
    dates = LibGit2.with(LibGit2.GitRevWalker(repo)) do walker
        LibGit2.map((oid, repo) -> get_date(LibGit2.GitCommit(repo, oid)), walker, by=LibGit2.Consts.SORT_TIME)
    end
    return extrema(dates)
end

"""
    months_list(path, start_month, end_month)

Get the range of months when there have been commit to the Git repository at
`path`, between `start_month` and `end_month`.
"""
function months_list(path, start_month, end_month)
    min_month, max_month = extrema_dates(path)
    min_month = max(Date(year(min_month), month(min_month)), start_month)
    max_month = min(Date(year(max_month), month(max_month)), end_month)
    return min_month:Month(1):max_month
end

"""
    checkout_date(path, date::Date; branch="master")

Check out `branch` of Git repository at `path` on `date`.
"""
function checkout_date(path, date::Date;
                       branch="master",
                       )
    revision = readchomp(`git -C $(path) rev-list -n 1 --first-parent --before="$(date) 00:00:00 +0000" $(branch)`)
    LibGit2.checkout!(GitRepo(path), revision)
end

"""
    count_packages(path, packages=TOML.parsefile(joinpath(path, "Registry.toml"))["packages"])

Count the number of packages in the registry at `path`, using the list of
`packages`.
"""
function count_packages(path,
                        packages=TOML.parsefile(joinpath(path, "Registry.toml"))["packages"])
    return length(packages)
end

"""
    _non_yanked_versions(file)

Get the list of non-yanked versions of the package for which `file` is the path
to its `Versions.toml`.
"""
function _non_yanked_versions(file)
    toml = TOML.parsefile(file)
    collect(k for (k, v) in toml if !(haskey(v, "yanked") && v["yanked"]))
end

"""
    count_versions(path, packages=TOML.parsefile(joinpath(path, "Registry.toml"))["packages"])

Count the number of versions in the registry at `path`, using the list of
`packages`.
"""
function count_versions(path,
                        packages=TOML.parsefile(joinpath(path, "Registry.toml"))["packages"])
    paths = joinpath.(path, getindex.(values(packages), "path"))
    isempty(paths) && return 0
    return sum(isfile(joinpath(p, "Versions.toml")) ? length(_non_yanked_versions(joinpath(p, "Versions.toml"))) : 0 for p in paths)
end

"""
    registry_activity(path=clone_registry();
                      branch="master",
                      start_month=Date(2018, 2),
                      end_month=Date(year(now(UTC)), month(now(UTC))),
                      filter=p->!(occursin(r"_jll\$", last(p)["name"]) || last(p)["name"]=="julia"),
                      )

Get the 3-tuple `months, packages, versions` of vector of months, number of
packages, number of versions for the registry at `path` (by default a Git clone
of the General registry with [`clone_registry()`](@ref)), checking out the Git
`branch`.  The search is restricted between `start_month` and `end_month`.  You
can filter the packages matching the `filter` condition, which is a function
taking as argument an item in the dictionary of a parsed `Registry.toml`, that
is a pair whose key is the UUID of the package and the value is a dictionary
with information about the package, usually including the name and the path to
the directory where the package is recorded.
"""
function registry_activity(path=clone_registry();
                           branch="master",
                           # By default start from the first month there has
                           # been some actual activity in General
                           start_month=Date(2018, 2),
                           end_month=Date(year(now(UTC)), month(now(UTC))),
                           # By default exclude JLL packages and the virtual "julia" package
                           filter=p->!(occursin(r"_jll$", last(p)["name"]) || last(p)["name"]=="julia"),
                           )
    repo = LibGit2.GitRepo(path)
    commit = LibGit2.GitHash(LibGit2.lookup_branch(repo, branch))
    LibGit2.checkout!(repo, string(commit))
    months = months_list(path, start_month, end_month)
    packages = Vector{Int}(undef, length(months))
    versions = Vector{Int}(undef, length(months))
    for idx in eachindex(months)
        # Check out the registry at midnight of the first day of the month after
        checkout_date(path, months[idx] + Month(1))
        packages_list = if isfile(joinpath(path, "registry.toml"))
            # The registry file used to be call "registry.toml" at some point.
            TOML.parsefile(joinpath(path, "registry.toml"))["packages"]
        else
            TOML.parsefile(joinpath(path, "Registry.toml"))["packages"]
        end
        filter!(filter, packages_list)
        packages[idx] = count_packages(path, packages_list)
        versions[idx] = count_versions(path, packages_list)
    end
    # Restore target commit.
    LibGit2.checkout!(repo, string(commit))
    return months, packages, versions
end

end # module
