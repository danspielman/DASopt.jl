using Documenter
using DASopt

makedocs(
    sitename = "DASopt",
    format = Documenter.HTML(prettyurls = false),
    modules = [DASopt]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
