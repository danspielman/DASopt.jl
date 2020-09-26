module DASopt

# Write your package code here.

using FileIO, JLD, Optim, Dates, Random, Distributed

include("try_many.jl")
export try_many, try_many_trans

include("Popevolve.jl")
export popevolve

include("Randline.jl")
export randline

include("optim_wrap.jl")
export optim_wrap, optim_wrap_many

end
