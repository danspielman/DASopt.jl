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
    record = nothing,
    optim_out=nothing,
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
- `optim_out` if set to an array, like [], then the output of Optim is pushed into it.

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
    record = nothing,
    optim_out = nothing,
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
        optfunc, options, autodiff, n_starts, optim_out)

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
This one assumes one vector input, rather than a generator.
=#
function optim_wrap(f::Function, x0::Array, mapin=identity;
    nrounds=1,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    autodiff = :finite,
    optim_out = nothing,
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
        if isa(optim_out, Vector)
            push!(optim_out, opt)
        end
        best = opt.minimizer
        val = fixed_f(best)
        x0 = mapin(best)
    end

    return val, x0
end

#=
The following is the old interface, which the new interface calls.
This one takes a generator as input, and it calls the one that takes a vector
=#
function optim_wrap(f::Function, gen::Function, mapin=identity;
    nrounds=1,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    autodiff = :finite,
    optim_out = nothing,
    n_starts = 0)

    fixed_f(z) = f(mapin(z))

    if n_starts > 1 
        _, x0  = try_many(fixed_f, gen, sense, n_tries = n_starts, verbosity=0)
    else
        x0 = gen()
    end 

    optim_wrap(f, x0, mapin;
        nrounds,
        optfunc,
        sense,
        options,
        optim_out,
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
    nrounds=1,
    optfunc=NelderMead(),
    autodiff = :finite,
    sense = :Max,
    options = Optim.Options(),
    n_starts = 0,
    par_batch = 0,
    threads = 0,
    record = nothing,
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

    return try_many_trans(fsub, ()->Nothing, sense;
        n_tries, 
        t_lim,
        file_base,
        verbosity,
        seed,
        local_rng,
        par_batch,
        threads,
        stop_val,
        record)
end


"""
An optim wraper that runs for t_lim on one core.
It is based on optim_wrap_many and try_many_trans.
The reason is is not inside of those is that it violates the abstraction of
try_many_trans by updating the time left for Optim at each call.

Counts how many calls to optim converge.
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
    record = nothing,
    iters = [],
    report_converged = [],
    thisid = 0,
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

    n_converged = 0

    while (time() < t_stop && comp(stop_val, bestval))

        tdo = Dict(fn=>getfield(options, fn) for fn ∈ fieldnames(typeof(options)))
        tdo[:time_limit] = t_stop - time()
        options = Optim.Options(;tdo...)

        optim_out = []

        a = optim_wrap(f, gen, mapin;
        nrounds,
        optfunc,
        sense,
        options,
        autodiff,
        n_starts,
        optim_out)

        isa(record, Vector) && push!(record, a)
        #!isnothing(record.val) && push!(record.val, a[1])
        #!isnothing(record.vec) && push!(record.vec, a[2])

        i += 1
        n_converged += Optim.converged(optim_out[1])

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
        println("Ran for $(i) iterations (converged on $(n_converged)) and $(time()-t0) seconds. Val: $(first_number(besta))")
    end

    if thisid > 0 && length(iters) >= thisid
        iters[thisid] = i
    end

    if thisid > 0 && length(report_converged) >= thisid
        report_converged[thisid] = n_converged
    end

    # REMOVE LATER: IS CHECKING FOR DETERMINISM
    #=
    val = f(besta[2])
    if abs(val - besta[1]) > 1e-8
        println("Value disagreement")
        println("just computed $val, but had")
        println(besta)
    end
    =#

    return besta
end

"""
    val, x = optim_wrap_tlim(sense, f::Function, gen::Function, mapin=identity;
        t_lim = 0,
        procs = 0,
        file_base = "",
        verbosity = 1 + verbose,
        seed = false,
        nrounds=1,
        optfunc=NelderMead(),
        autodiff = :finite,
        options = Optim.Options(),
        n_starts = 0,
        record = nothing,
        report_iters = nothing,
        report_converged = nothing,
        stop_val = sensemap(sense) == :Max ? Inf : -Inf)

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
    record = nothing,
    report_iters = nothing,
    report_converged = nothing,
    stop_val = sensemap(sense) == :Max ? Inf : -Inf)

    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    if t_lim == 0
        @warn "t_lim should be set to something > 0"
        t_lim = 0.1
    end

    parallel = isdefined(Main, :nprocs) && nprocs() > 1 && procs > 1

    if parallel
        capture_iters = SharedVector(zeros(Int, procs))
        for j in 1:procs
            capture_iters[j] = 0
        end

        capture_converged = SharedVector(zeros(Int, procs))
        for j in 1:procs
            capture_converged[j] = 0
        end
    else
        procs = 0
        capture_iters = Int[0]
        capture_converged = Int[0]
    end


    # sub_verbosity = procs > 0 ? max(0,verbosity-1) : verbosity
    sub_verbosity = max(0,verbosity-1)

    if parallel
        sub = j->optim_wrap_tlim1(sense, f, gen, mapin; 
            t_lim,
            file_base,
            verbosity = sub_verbosity, 
            seed,
            nrounds,
            optfunc,
            autodiff,
            options,
            n_starts,
            record,
            iters = capture_iters,
            report_converged = capture_converged,
            thisid = j,
            stop_val)
    else
        sub = ()->optim_wrap_tlim1(sense, f, gen, mapin; 
        t_lim,
        file_base,
        verbosity = sub_verbosity,
        seed,
        nrounds,
        optfunc,
        autodiff,
        options,
        n_starts,
        record,
        iters = capture_iters,
        report_converged = capture_converged,
        thisid = 1,        
        stop_val)       
    end

    t0 = time()

    iters = 0
    n_converged = 0

    if !parallel
        a = sub()
        iters = capture_iters[1]
        n_converged = capture_converged[1]
    else
        keepbest(a,b) = comp(first_number(a), first_number(b)) ? a : b
        outputs = pmap(j->sub(j), 1:procs)
        a = reduce(keepbest, outputs)
        iters = sum(capture_iters)
        n_converged = sum(capture_converged)
    end

    isa(report_iters, Vector) && push!(report_iters, iters)
    isa(report_converged, Vector) && push!(report_converged, n_converged)

    if verbosity > 0
        if verbosity == 1
            print("Ran for $(time()-t0) seconds and $iters total iters (converged $(n_converged)). ")
        end
        println("Val: $(a[1])")
#        println("$(a[2])")
#        println("Val: $(a[1])")
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