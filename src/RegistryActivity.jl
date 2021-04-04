module RegistryActivity

# Note about the statistics of the General registry: about 15k versions and 600
# packages were removed in October 2019 with
# https://github.com/JuliaRegistries/General/pull/4169.  It's complicated to
# deal with this because some packages had only some versions removed, others
# got completely removed and then they came back into the registry later.

using Pkg, Dates, LibGit2, TOML

export registry_activity

# Try to find the local copy of the Genral registry.  NOTE: it may or may *not*
# be a git repository
find_general() = joinpath(Pkg.depots()[1], "registries", "General")

function clone_registry(;
                        origin="https://github.com/JuliaRegistries/General.git",
                        dest=mktempdir(),
                        )
    LibGit2.clone(origin, dest)
    return dest
end

# Get the date of the commit
function get_date(c)
    committer = LibGit2.committer(c)
    return Date(unix2datetime(committer.time + 60 * committer.time_offset))
end

function extrema_dates(path)
    repo = GitRepo(path)
    # Find the dates of all commits in the repo
    dates = LibGit2.with(LibGit2.GitRevWalker(repo)) do walker
        LibGit2.map((oid, repo) -> get_date(LibGit2.GitCommit(repo, oid)), walker, by=LibGit2.Consts.SORT_TIME)
    end
    return extrema(dates)
end

function months_list(path, start_month, end_month)
    min_month, max_month = extrema_dates(path)
    min_month = max(Date(year(min_month), month(min_month)), start_month)
    max_month = min(Date(year(max_month), month(max_month)), end_month)
    return min_month:Month(1):max_month
end

function checkout_date(path, date::Date;
                       branch="master",
                       )
    revision = readchomp(`git -C $(path) rev-list -n 1 --first-parent --before="$(date) 00:00:00 +0000" $(branch)`)
    LibGit2.checkout!(GitRepo(path), revision)
end

function count_packages(path,
                        packages=TOML.parsefile(joinpath(path, "Registry.toml"))["packages"])
    return length(packages)
end

function _non_yanked_versions(file)
    toml = TOML.parsefile(file)
    collect(k for (k, v) in toml if !(haskey(v, "yanked") && v["yanked"]))
end

function count_versions(path,
                        packages=TOML.parsefile(joinpath(path, "Registry.toml"))["packages"])
    paths = joinpath.(path, getindex.(values(packages), "path"))
    isempty(paths) && return 0
    return sum(isfile(joinpath(p, "Versions.toml")) ? length(_non_yanked_versions(joinpath(p, "Versions.toml"))) : 0 for p in paths)
end

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
