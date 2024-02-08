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

Reporting options from the code require FileIO and JLD.

There are long docstrings for the main functions:
* `try_many`
* `optim_wrap`
* `optim_wrap_tlim`
* `popevolve`

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
* A function to be optimized, henceforth called `obj`. It should take a vector or matrix input.
* A 0-argument function `gen` that generates random inputs on which to run `opt`. For example, if `obj` takes as input 3-by-3 matrices, you could use `()->randn(3,3)`
* A `mapin` function.  Every input will be passed through `mapin`, so the random inputs from `gen` will always be passed through `mapin`. If you don't need a `mapin` function, just use the identity, `identity`. This is the default.

# Examples

For the examples, we'll try to maximize the following function over the positive reals:

~~~julia
function f(x)
    n = length(x)
    x = n * x ./ sum(x)
    sum( (sqrt.(1:n) .* (1 .+ x)).^(-(1:n)) )
end
~~~

## `try_many`

The simplest thing to do is to evaluate it many times, and return the best answer.
The function `try_many` does this.
It's arguments are, in order
- whether you want to maximize or minimize, entered like `:max` or `:min` or `min` or `:Min`. 
- the function
- the generator
- and, you'd better either limit the number of tries with n_tries, or the time with t_lim (in seconds), or it will only run once and scold you after.

~~~julia
gen = ()->abs.(randn(n))
val, x = try_many(:max, f, gen, n_tries = 100)
~~~

```
ran for 100 iterations and 7.891654968261719e-5 seconds
(1.45104084111684, [0.2799444996557729, 0.023175686802835525, 0.02790830600759088, 0.6327642887723712, 3.247489664339628, 1.970732866560268, 0.5444613790178201, 0.12878273941192095, 1.6213544653435499, 1.8005802412405592])
```

or,

~~~julia
gen = ()->abs.(randn(n))
val, x = try_many(:max, f, gen, t_lim = 10)
~~~
```
ran for 25667613 iterations and 10.0 seconds
(1.724822634882288, [0.007115492560127166, 0.0060218764236192966, 0.007058974308850966, 0.002251973892562873, 1.294639906864887, 1.3603254435013257, 1.4052092338466922, 0.3638162884606654, 1.2019147032132087, 0.14683884086626892])
```

## `optim_wrap`

Or, we could use the optimization heuristics supplied by Optim.jl.
Here, we'll run it once and use a `mapin` function to make the input vector non-negative.

~~~julia
mapin(x) = abs.(x)
val, x = optim_wrap(:max, f, ()->randn(n), mapin)
~~~
```
(1.7734985707334308, [8.39434561247921e-5, 0.00012424402997208802, 0.00020035710940736397, 2.5159920185916727e-8, 9.968906828488826e-9, 0.19678042428047735, 1.7629768354561528, 0.3063347958458918, 1.094806043147923, 3.872347373117642])
```

If you'd like the actual output of `Optim`, say to find out why it stopped when it did, pass an empty array as an optional parameter `optim_out`, like this

~~~julia
optim_out = []
val, x = optim_wrap(:max, f, randn(n), mapin; optim_out)
~~~

That's some idiosyncratic Julia that is equivalent to
~~~julia
oo = []
val, x = optim_wrap(:max, f, randn(n), mapin; optim_out=oo)
~~~

When you look at `optim_out[1]` (or `oo[1]` in the second version), it will tell you why `Optim` stopped running. To deal with it programmatically, you can find a list of the fields inside it by 
~~~julia
fieldnames(typeof(optim_out[1]))
~~~

For example. to find the number of iterations for which it ran, look at
~~~julia
optim_out[1].iterations
~~~

By default, `Optim` will stop after 1000 iterations. You can pass options to `Optim` to try running for longer, like this.

~~~julia
using Optim
optim_out = []
val, x = optim_wrap(:max, f, randn(n), mapin; optim_out, 
    options = Optim.Options(iterations=10_000))
~~~
```
(1.7774757759766937, [4.023537986548861e-8, 3.98980950460594e-8, 2.0873442725052612e-7, 3.2538420220220974e-8, 1.457651648215776e-7, 7.000558921398792e-7, 3.5531868787344005, 1.602793377169931, 2.1782442039752707, 18.192652050165087])
```

Sometimes this will help it come closer to the right value.

### Running many times

It's still not coming close to the right value.
So, we might want to run it many times, and then take the best.
We can either tell it how many times we want it to run, or we can set a time limit.

The advantage of running many times is that each time we start Optim from a random input, in this case the one given by the generator `randn(n)`. 
While most routines used by Optim are deterministic, starting optimizing from a different point each time will vary the results.

~~~julia
val, x = optim_wrap(:max, f, ()->randn(n), mapin, t_lim=10)
~~~
```
ran for 11296 iterations and 10.000691890716553 seconds
(1.778808950702666, [2.5066053964552477e-8, 1.671287683128166e-8, 1.506142468701956e-8, 3.851122643738583e-8, 3.5727351220010217e-7, 4.602784698036007e-7, 2.1315694987929577e-6, 0.006798927685564552, 3.3046431030660024, 21.138435211421285])
```

That is coming a lot closer to the solution.
We could try to get even closer by taking that vector and starting from it. For this, we would call `optim_wrap` with one vector as input, rather than a generator, like this.

~~~julia
val2, x2 = optim_wrap(:max, f, x, mapin)
~~~
```
(1.7788650863478543, [7.569392396677863e-9, 7.42283483111358e-8, 4.9991472554374096e-8, 4.481405854555795e-8, 3.786422339592463e-7, 8.867942335218281e-7, 4.206349096433922e-8, 1.7589863466327837e-5, 0.0002587898154322173, 55.5952871735933])
```

This comes very close to what I believe to be the optimal solution.

~~~julia
n = 10
xs = zeros(10)
xs[10] = 1
bestval = f(xs)
~~~
```
1.7788651463070229
```

### Other optimization functions

We can use other optimizers provided by Optim, like this.

~~~julia
using Optim
val, x = optim_wrap(:max, f, ()->randn(n), x->abs.(x), optfunc=LBFGS())
~~~
```
(1.7785702013750266, [2.1919045027547362e-17, 6.052728403732219e-17, 5.088278283321528e-17, 3.445083119221125e-17, 1.7365323604089583e-16, 7.709998792025272e-16, 1.8132465363571096e-15, 2.5501904120707195, 2.583935183796174, 1.091193407482604])
```

If you get an error from LBFGS, I suggest running it with a different linesearch, like 
~~~julia
optfunc = LBFGS(;linesearch = LineSearches.BackTracking())
~~~

You might be tempted to incorporate the mapin function directly into the objective function, like this:

~~~julia
val, x = optim_wrap(:max, x->f(abs.(x)), ()->randn(n), optfunc=LBFGS())
~~~
```
(1.7785702010851563, [-7.774443564306855e-16, -1.0984237963132328e-16, -8.53702152089751e-16, -7.878099274331449e-16, -5.041416224833228e-15, -2.0780442009829583e-14, 2.318635868490806e-14, 5.501508367329071, 4.673330205658298, -3.3213287817366846])
```

That's fine, except that the vector it returns won't be in the positive orthant. So, you have to remember to correct it.

But, there's another reason to use a `mapin` function.
If you would like a higher precision solution, one way to get it is to run `optim_wrap` on the output of itself.
This is particularly useful if the `mapin` function is complicated.
The first time you run, the algorithm could be working over a very strange parameterization of the problem, whereas if you start from the result of running `mapin` near the solution, then it will likely be working near the right parameterization. At least, this is true if `mapin(mapin(x)) = mapin(x)`.
To run optim on its own output automatically, you can tell optim_wrap to run for a certain number of rounds, like this.

~~~julia
val, x = optim_wrap(:max, f, ()->randn(n), mapin, t_lim=10, nrounds=3)
~~~
```
ran for 11395 iterations and 10.000854015350342 seconds
(1.778767083914744, [2.8190101073936208e-8, 3.1626540076700813e-8, 2.470341683198151e-8, 1.6700499549683346e-7, 4.388544561589988e-7, 2.442235976309889e-7, 0.0061570358280002655, 0.06753328773048227, 14.420282131977224, 21.19838690955713])
```

That ran on its own output 3 times.

## `optim_wrap_tlim` (parallel optimization)

If you look at `optim_wrap`, you will see that it has flags to let you run in parallel.
But, the code `optim_wrap_tlim` is more efficient at this.
Here's an example of how you use it.
You do need to tell it on how many processors you want to run.
If you don't give it a number of processors, then it will be equivalent `optim_wrap`.
This is actually useful for debugging, because interrupting code running in parallel often causes the kernel to crash. So, you should debug the serial version first.

It is often easiest to put the function you want to optimize into a `.jl` file, and the include it like
~~~julia
@everywhere include("myfun.jl")
~~~

~~~julia
using Distributed
addprocs()
@everywhere using DASopt
@everywhere include("myfun.jl")
val, x = optim_wrap_tlim(:max, f, ()->randn(n), x->abs.(x), t_lim = 10, procs=10)
~~~
```
Ran for 10.233434200286865 seconds and 105077 total iters (converged 82487). Val: 1.7772689981819667
```

Each of these reported iterations is a fresh run of Optim from a different random starting point.
We also report the number of these iterations in which Optim reached its stopping criteria.
When it doesn't converge, it is usually because either it has run out of time, it took too many iterations, or did something else too many times.
In this case, you might want to pass options to Optim to let it run for longer.
Above, we saw how to increase the number of iterations it will run.
Note that these are the iterations of its internal routine, not the iterations we report above.

`optim_wrap` also has multi-threaded versions, but those don't perform as well.

~~~julia
val, x = optim_wrap(:max, f, ()->randn(n), x->abs.(x), t_lim = 10, threads=th)
~~~
```
ran for 22852 iterations and 10.00054407119751 seconds
```

## parallel tip

If you have data that is needed by remote workers and they don't find it, try pushing it to them with a line like:
~~~
for i in procs()
    remotecall_fetch(()->M, i);
end
~~~

Warning: The way that the multithreaded and distributed code in DASopt handles the pseudo-random generators hasn't been updated in a long time, and can be greatly improved. Julia makes it easier now.

## `popevolve`

`popevolve` is a heuristic based on Differential Evolution (Storn & Price, Journal of Global Optimization, 1997)
It is wonderful for some problems.
It's syntax is pretty similar to that of optim_wrap.

~~~julia
val, x = popevolve(:max, f, ()->randn(10), x->abs.(x), t_lim = 1)
~~~
```
Best val: 1.778853249903231, after 1 runs with a total of 776 rounds.
(1.778853249903231, [3.2920579242606934e10, 1.4605875968851248e11, 5.373745668834381e10, 2.2954069733566406e11, 5.03076331130126e11, 1.0576080730186523e11, 1.6485943354736406e12, 7.82545710281767e13, 6.7244040061764e13, 4.2866741659809485e17])
```

This generated a really good answer in a short time.
In fact, for this function it dominates all the algorithms we've seen so far.
Although, the magnitude of the vector `x` suggests that some normalization might be in order, like this.

~~~julia
mapin(x) = (y = abs.(x); y / sum(y))
val, x = popevolve(:max, f, ()->randn(10), mapin, t_lim = 1)
~~~
```
(1.7788651463070229, [8.728772535926254e-18, 7.97175336549306e-18, 8.33853638971245e-18, 2.3191545898422126e-17, 3.109442113738381e-17, 6.568467331324206e-16, 9.297832174842915e-16, 1.4084180692887493e-15, 3.243187273130337e-15, 0.9999999999999937])
```

That's the right answer to 16 digits!

We can also run it multi-threaded or in parallel.

~~~julia
val, x = popevolve(:max, f, ()->randn(10), mapin, t_lim = 1, threads=true)
~~~
```
Best val: 1.7788651463070229, after 1 runs with a total of 2014 rounds.
(1.7788651463070229, [7.405608709735076e-18, 5.061431442052532e-18, 7.199065121512007e-18, 2.832269241265389e-17, 1.0390321357917905e-16, 5.022084052329539e-16, 1.1490779787497575e-15, 2.100565140641972e-15, 0.0008420344186849803, 0.9991579655813111])
```

~~~julia
val, x = popevolve(:max, f, ()->randn(10), mapin, t_lim = 1, parallel=true)
~~~
```
Best val: 1.7786939547935423, after 1 runs with a total of 81 rounds.
(1.7786939547935423, [2.5258692758104312e-6, 1.7165913669928014e-6, 1.605747781058081e-7, 1.701452774040192e-5, 2.4550477967603522e-5, 2.562358129986186e-5, 7.03449755455628e-5, 7.186561503843711e-6, 0.10281444029149907, 0.8970364365490227])
```

In this case the parallel code was slower. You can see that by observing that it ran for many fewer rounds.
The reason is that the function `f` is so simple that the overhead of the parallel code dominated.
For complex functions f, the parallel code will be better.

## output

You can control the amount of output of these routines by setting the `verbosity` parameter. 
- 0 suppresses output.
- 1 is the default. It just provides output at the end.
- 2 typically provides output for each - successive optimum. Expect a number of outputs logarithmic in the number of trials.
- 3 provides output for every call of Optim.

But, the parallel code decreases the verbosity by 1 for the worker processes.

## Other options
These are some other options that can be set for some of these functions.

- `stop_val` : if you are just trying to find out if the optimum can be made better than some x, then set `stop_val` to this x. The routines will stop as soon as they find an example that satisfies this.

- `n_starts` : rather than trying to optimize starting from a random vector (output by `gen`), we take `n_starts` samples from `gen`, find the best of them, and then start optimizing from it.


## more documentation


To build the documentation for this locally, go to the package directory
(probably under .julia/packages/DASopt/ ) to find the right one, try
`] st DASopt`. Then type `julia docs/make.jl`. The docs will appear in `docs/build/index.html'
