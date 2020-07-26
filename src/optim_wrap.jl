
"""
    x, val = optim_wrap(f, x0, mapin;
    nrounds=3,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    n_starts = 0)

# Arguments
- `f` is a nonlinear func to optimize
- `x0` is an initial point. Instead of being a vector, `x0` can be a generator, `like ()->rand(3)`
- `mapin` is a function applied to things like `x` to put in range.
- We run for `nrounds`, with a `mapin `at the end of each to polish.
- The `n_starts` option then tells us to start from the best of `n_starts`runs.
"""
function optim_wrap(f, x0::Array, mapin;
    nrounds=3,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options())

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
        opt = Optim.optimize(f_opt, x0, optfunc , options)
        best = opt.minimizer
        val = fixed_f(best)
        x0 = mapin(best)
    end

    return x0, val
end

function optim_wrap(f, gen::Function, mapin;
    nrounds=3,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    n_starts = 0)

    fixed_f(z) = f(mapin(z))

    if n_starts > 0
        x0 = try_many(fixed_f, gen, sense, n = n_starts, verbosity=0)
    else
        x0 = gen()
    end

    optim_wrap(f, x0, mapin,
        nrounds=nrounds,
        optfunc=optfunc,
        sense=sense,
        options=options)
end




"""
    x, val = optim_wrap_many(f, x0, mapin; n = Inf, t_lim = Inf,
        nrounds=3,
        optfunc=NelderMead(),
        sense = :Max,
        options = Optim.Options(),
        n_starts = 0,)

    val, best = optim_wrap_many(f, x0fun, mapin, nruns;
    nrounds, optfunc, maxevals, sense,
    file=[])

Essentially optim_wrap inside try_many. Kwargs come from both.
At least one of n or t_lim must be set.
"""
function optim_wrap_many(f::Function, gen::Function, mapin;  n = Inf, t_lim = Inf,
    fn_base = "",
    verbose = false,
    verbosity = 1 + verbose,
    seed = false,
    local_rng = false,
    nrounds=3,
    optfunc=NelderMead(),
    sense = :Max,
    options = Optim.Options(),
    n_starts = 0)

    if t_lim < Inf
        tdo = Dict(fn=>getfield(options, fn) for fn ∈ fieldnames(typeof(options)))
        tdo[:time_limit] = t_lim
        options = Optim.Options(;tdo...)
    end

    fsub(x) = optim_wrap(f, gen, mapin,
        nrounds=nrounds,
        optfunc=optfunc,
        sense = sense,
        options = options,
        n_starts = n_starts)

    # if t_lim, put that into options

    return try_many_trans(fsub, ()->Nothing, sense, n = n, t_lim = t_lim,
        fn_base = fn_base,
        verbosity = verbosity,
        seed = seed,
        local_rng = local_rng)


end
