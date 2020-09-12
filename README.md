# DASopt

This package contains wrappers for naive optimization routines and Optim that I (Dan Spielman) have found very useful in my research.  It, of course, requires Optim.
It is written for unconstrained optimization.  However, many of the functions we want to optimize are subject to constraints. So, we employ a "mapin" function that maps arbitrary vectors into vectors that satisfy the constraints.

[Docstrings for the functions may be found here.](built_docs/index)

Reporting options from the code require FileIO and JLD.

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
