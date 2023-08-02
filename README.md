# DASopt

This package contains optimization heuristics that I (Dan Spielman) have found very useful in my research.  The ones I most use are wrappers for Optim. I
It is written for unconstrained optimization.  However, many of the functions we want to optimize are subject to constraints. So, we employ a "mapin" function that maps arbitrary vectors into vectors that satisfy the constraints.

I make no guarantees about the correctness, robustness, or suitability of this code.
Some of the functions are very old, and might not work with current Julia packages.
It is merely something that I and some of my group find useful.

To install, type
~~~
using Pkg
Pkg.add(url="https://github.com/danspielman/DASopt.jl")
~~~

Or, if in the Julia shell type `]` to get to the package prompt, and then
~~~
add https://github.com/danspielman/DASopt.jl
~~~

**Warning**: with this version, we swap the order of outputs. We now give the value before the vector. This change was made on Jan 25, 2023.

Reporting options from the code require FileIO and JLD.

There are long docstrings for the main functions:
* `try_many`
* `optim_wrap`
* `optim_wrap_many`

You can view them in Julia by typing things like `?try_many`.

The documentation should be automatically generated when you add the package. The root of the documentation can be found by typing
~~~
using DASopt
println(DASopt.docsdir())
~~~
This will return the index page for the documentation.
I suggest you open it in a browser, and bookmark it.

Please improve the documentation!



The optimization routines require:
* A function to be optimized, henceforth called `obj`
* A function `gen` that generates random inputs on which to run `opt`
* A `mapin` function.  Every input will be passed through `mapin`, so the random inputs from `gen` will always be passed through `mapin`. If you don't need a `mapin` function, just use the identity, `id`.

The simplest function is `try_many`.
It just evaluates `obj` on many random inputs.

To use multiple threads to evaluate in parallel, set `threads` to the size of the batch that you want to run. This would normally be many times the number of threads available. Distributed is usually faster, but trickier to use.

To use any of these in parallel, one must:
- type `using Distributed`
- `addprocs()`
- `@everywhere using DASopt`
-  `@everywhere` define every function you are using

If you have data that is needed by remote workers and they don't find it, try pushing it to them with a line like:
~~~
for i in procs()
    remotecall_fetch(()->M, i);
end
~~~

Warning: The way that the multithreaded and distributed code handle the pseudo-random generators hasn't been updated in a long time, and can be greatly improved. Julia makes it easier now.


To build the documentation for this locally, go to the package directory
(probably under .julia/packages/DASopt/ ) to find the right one, try
`] st DASopt`. Then type `julia docs/make.jl`. The docs will appear in `docs/build/index.html'
