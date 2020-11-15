# DASopt

This package contains wrappers for naive optimization routines and Optim that I (Dan Spielman) have found very useful in my research.  It, of course, requires Optim.
It is written for unconstrained optimization.  However, many of the functions we want to optimize are subject to constraints. So, we employ a "mapin" function that maps arbitrary vectors into vectors that satisfy the constraints.


Reporting options from the code require FileIO and JLD.

There are long docstrings for the main functions:
* `try_many`
* `optim_wrap`
* `optim_wrap_many`

You can view them in Julia by typing things like `?try_many`.

To generate more detailed documentation, that you can then view on your own machine,
go to the `docs` directory, with is probably under `~/.julia/packages/DASopt/junk/docs`, 
where "junk" is a hash so you should just go to the most recent directory,
and when you are there type `julia make.jl`.
This will put docs into a `build` directory.
Open `index.html` in your browser, and bookmark it.



The optimization routines require:
* A function to be optimized, henceforth called `obj`
* A function `gen` that generates random inputs on which to run `opt`
* A `mapin` function.  Every input will be passed through `mapin`, so the random inputs from `gen` will always be passed through `mapin`. If you don't need a `mapin` function, just use the identity, `id`.

The simplest function is `try_many`.
It just evaluates `obj` on many random inputs.

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

To build the documentation for this locally, go to the package directory
(probably under .julia/packages/DASopt/ ) to find the right one, try
`] st DASopt`. Then type `julia docs/make.jl`. The docs will appear in `docs/build/index.html'
