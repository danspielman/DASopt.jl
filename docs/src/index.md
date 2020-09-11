# DASopt.jl

# The optimization wrappers

* `try_many` is designed to evaluate a function on many random inputs.
* `optim_wrap` is a wrapper around `Optim`.
* `optim_wrap_many` uses `try_many` to call `optim_wrap` from many random initial points.

To the extent that parameters of `optim_wrap_many` are inherited from `optim_wrap` and `try_many`, they are described in those routines.


```@docs
try_many
optim_wrap
optim_wrap_many
```

# Other optimization heuristics


```@docs
popevolve
```