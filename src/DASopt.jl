module DASopt

# Write your package code here.

using FileIO, JLD, Optim, Dates, Random, Distributed, ThreadsX
using LinearAlgebra, Statistics

include("try_many.jl")
export try_many, try_many_trans

include("Popevolve.jl")
export popevolve

include("Randline.jl")
export randline

include("optim_wrap.jl")
export optim_wrap, optim_wrap_many

include("GoWin.jl")
export gowin
end
