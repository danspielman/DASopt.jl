"""
    val, x = optim_wrap(sense, obj, x0 / gen, mapin=identity;
    n_tries = Inf, t_lim = Inf, 
    nrounds=(mapin==identity ? 1 : 2),
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    n_starts = 0,
    par_batch = 0,
    threads = 0,
    record = Record(),
    stop_val = Inf or -Inf depending on sense)

A wrapper for `Optim`.  
Adds a few features that I find helpful, especially when I want to optimize over a manifold or odd parameter space.
The function `mapin` should take an aribtrary vector (or matrix) input and map it to the space of interest.
`mapin` will always be applied before `f`.

As `mapin` can do strange things to the vector, `Optim` might not be working in the right parameter space.
For this reason, it is helpful to occasionally stop optim, apply `mapin` to the current optimum,
and then restart `Optim` from that point.
This code does this `nrounds` times.
If it seems unnecessary, say if `mapin = identity`, then set `nrounds=1`.

As `Optim` can run for a while, we might be able to improve it by starting from the best of many inputs.
If `n_starts > 1`, the code will call `gen` to generate `n_starts` and then start `Optim` from the best of these.

A major feature is that it uses `try_many` to run many trials.
So, it inherits all the inputs of `try_many`.
This was called `optim_wrap_many` in the previous version.
If neither t_lim nor n_tries are set, it just runs once.

# Arguments
- `sense` should be :Min or :Max
- `f` is a nonlinear func to optimize
- `x0` is an initial point. Instead of being a vector, it can be a generator like `()->rand(3)`
- `mapin` is a function applied to things like `x` to put in range.
- We run for `nrounds`, with a `mapin `at the end of each to polish.
- The `n_starts` option then tells us to start from the best of `n_starts`runs.
- `optfunc` is the name of an optimizer that Optim uses.
- `options` are options for Optim, with the default generated by `Optim.Options()`
- `autodiff` is passed to Optim. The default is `:finite` when you want it, you want `:forward`.


"""
function optim_wrap(sense::Symbol, obj::Function, gen, mapin=identity;
    t_lim = Inf, n_tries = Inf,
    nrounds=(mapin==identity ? 1 : 2),
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    file_base = "",
    verbose = false,
    verbosity = 1 + verbose,
    seed = false,
    local_rng = false,
    n_starts = 0,
    par_batch = 0,
    threads = 0,
    record = Record(),
    stop_val = (sense == :Max || sense == :max) ? Inf : -Inf)
    
    if sense == :max 
        sense = :Max
    end
    if sense == :min
        sense = :Min
    end

    if t_lim == Inf && n_tries == Inf

        val, x = optim_wrap(obj, gen, mapin;
        sense,
        nrounds,
        optfunc, options, autodiff, n_starts)

    else

        val, x = optim_wrap_many(obj, gen, mapin;
        sense,
        n_tries, t_lim, 
        verbosity,
        file_base, record,
        nrounds = (mapin==identity ? 1 : 2),
        optfunc, options, autodiff,
        n_starts,
        par_batch, threads, 
        stop_val)
    end

end

optim_wrap(sense::typeof(min), obj::Function, args...; kwargs...) = optim_wrap(:Min, obj, args...; kwargs...)
optim_wrap(sense::typeof(max), obj::Function, args...; kwargs...) = optim_wrap(:Max, obj, args...; kwargs...)



#=
The following is the old interface, which the new interface calls.
=#
function optim_wrap(f::Function, x0::Array, mapin=identity;
    nrounds=3,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    autodiff = :finite,
    n_starts = 0)

    @assert sense==:Max || sense==:Min

    if sense == :Max
        sgn = -1
        comp = >
    else
         sgn = 1
        comp = <
    end

    x0 = mapin(x0)
    fixed_f(z) = f(mapin(z))
    f_opt(z) = sgn*fixed_f(z)

    local val
    for i in 1:nrounds
        opt = Optim.optimize(f_opt, x0, optfunc , options; autodiff)
        best = opt.minimizer
        val = fixed_f(best)
        x0 = mapin(best)
    end

    return val, x0
end

function optim_wrap(f::Function, gen::Function, mapin=identity;
    nrounds=3,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    autodiff = :finite,
    n_starts = 0)

    fixed_f(z) = f(mapin(z))

    if n_starts > 1 
        x0, _  = try_many(fixed_f, gen, sense, n_tries = n_starts, verbosity=0)
    else
        x0 = gen()
    end 

    optim_wrap(f, x0, mapin;
        nrounds,
        optfunc,
        sense,
        options,
        autodiff)
end




#=
The following is the old interface, which the new interface calls.
=#
function optim_wrap_many(f::Function, gen::Function, mapin=identity;  n_tries = Inf, t_lim = Inf,
    file_base = "",
    verbose = false,
    verbosity = 1 + verbose,
    seed = false,
    local_rng = false,
    nrounds=3,
    optfunc=NelderMead(),
    autodiff = :finite,
    sense = :Max,
    options = Optim.Options(),
    n_starts = 0,
    par_batch = 0,
    threads = 0,
    record = Record(),
    stop_val = (sense == :Max || sense == :max) ? Inf : -Inf)

    if t_lim < Inf
        tdo = Dict(fn=>getfield(options, fn) for fn ∈ fieldnames(typeof(options)))
        tdo[:time_limit] = t_lim
        options = Optim.Options(;tdo...)
    end

    fsub(x) = optim_wrap(f, gen, mapin;
        nrounds,
        optfunc,
        sense,
        options,
        autodiff,
        n_starts)

    # if t_lim, put that into options

    return try_many_trans(fsub, ()->Nothing, sense, n_tries = n_tries, t_lim = t_lim,
        file_base = file_base,
        verbosity = verbosity,
        seed = seed,
        local_rng = local_rng,
        par_batch = par_batch,
        threads = threads,
        stop_val = stop_val,
        record = record)
end


"""
An optim wraper that runs for t_lim on one core.
It is based on optim_wrap_many and try_many_trans.
The reason is is not inside of those is that it violates the abstraction of
try_many_trans by updating the time left for Optim at each call.
"""
function optim_wrap_tlim1(sense, f::Function, gen::Function, mapin=identity; t_lim = 0,
    file_base = "",
    verbose = false,
    verbosity = 1 + verbose,
    seed = false,
    nrounds=1,
    optfunc=NelderMead(),
    autodiff = :finite,
    options = Optim.Options(),
    n_starts = 0,
    record = Record(),
    stop_val = sensemap(sense) == :Max ? Inf : -Inf)

    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    keepbest(a,b) = comp(first_number(a), first_number(b)) ? a : b

    besta = []
    bests = []

    if !isempty(file_base)
        txt_file = "$(file_base).txt"
        jld_file = "$(file_base).jld"
    else
        txt_file, jld_file = "", ""
    end

    !isempty(file_base) && verbosity > 0 &&
        println("writing to $(txt_file) and $(jld_file)")

    info_to_file(txt_file)

    t0 = time()
    t_stop = t0 + t_lim

    i = 0

    while (time() < t_stop && comp(stop_val, bestval))

        tdo = Dict(fn=>getfield(options, fn) for fn ∈ fieldnames(typeof(options)))
        tdo[:time_limit] = t_stop - time()
        options = Optim.Options(;tdo...)

        a = optim_wrap(f, gen, mapin;
        nrounds,
        optfunc,
        sense,
        options,
        autodiff,
        n_starts)

        !isnothing(record.val) && push!(record.val, a[1])
        !isnothing(record.vec) && push!(record.vec, a[2])

        i += 1

        val = first_number(a)

        if comp(val,bestval)
            bestval = val
            besta = a
            push!(bests,a)
            if verbosity >= 2
		        report(i, bestval, besta, txt_file)
            end
            !isempty(file_base) && save(jld_file, "bests", bests)
        elseif verbosity > 2
            println("iteration: $(i), val: $(val)")
        end
    end

    if verbosity > 0
        println("ran for $(i) iterations and $(time()-t0) seconds. Val: $(besta[1])")
    end

    return besta
end

"""
An optim wraper that runs for t_lim, and can run in parallel.
It is based on optim_wrap_many and try_many_trans.
The reason is is not inside of those is that it violates the abstraction of
try_many_trans by updating the time left for Optim at each call.

`procs` is the number of cores on which it runs.
"""
function optim_wrap_tlim(sense, f::Function, gen::Function, mapin=identity; t_lim = 0,
    procs = 0,
    file_base = "",
    verbose = false,
    verbosity = 1 + verbose,
    seed = false,
    nrounds=1,
    optfunc=NelderMead(),
    autodiff = :finite,
    options = Optim.Options(),
    n_starts = 0,
    record = Record(),
    stop_val = sensemap(sense) == :Max ? Inf : -Inf)

    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    sub = ()->optim_wrap_tlim1(sense, f, gen, mapin; 
        t_lim,
        file_base,
        verbosity,
        seed,
        nrounds,
        optfunc,
        autodiff,
        options,
        n_starts,
        record,
        stop_val)

    if procs == 0
        a = sub()
    else
        keepbest(a,b) = comp(first_number(a), first_number(b)) ? a : b
        outputs = pmap(j->sub(), 1:procs)
        a = reduce(keepbest, outputs)
    end

    if verbosity > 0
        println("$(a[2])")
        println("Val: $(a[1])")
    end

    return a

end

mutable struct EveryN
    n::Int
    i::Int
end

"""
    cnt = EveryN(n)

Every nth time `cnt()` is called it returns a 1. Otherwise it is 0.
"""
EveryN(n) = EveryN(n, 0)

function (cnt::EveryN)()
    cnt.i += 1
    if cnt.i == cnt.n
        cnt.i = 0
    end
    cnt.i == 0 ? 1 : 0
end

mutable struct EveryTic
    interval::Float64
    tbase::Float64
end

"""
    cnt = EveryTic(s)

cnt() will return 1 if the last time it returned 1 was at least `s` seconds ago.
Otherwise a 0.
"""
EveryTic(s) = EveryTic(s, time())

function (cnt::EveryTic)()
    out = 0
    t = time()
    if t > cnt.tbase + cnt.interval
        cnt.tbase = t
        out = 1
    end
    return out
end



# note t is in seconds
optim_tlim(t) = Optim.Options(iterations=typemax(Int),time_limit=t)