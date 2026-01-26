#=
This is the true optim wrapper, i.e. our base wrapper. Everything else is a wrapper around this wrapper.
=#
function optim_wrap(sense::Symbol, f::Function, x0::Array, mapin::Function=identity;
    nrounds::Int=1,
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    optim_out = nothing)

    sense = sensemap(sense)

    if sense == :Max
        sgn = -1
        comp = >
    else
        sgn = 1
        comp = <
    end

    x0 = mapin(x0)
    x = copy(x0)
    fixed_f(z) = f(mapin(z))
    f_opt(z) = sgn*fixed_f(z)

    local val
    for i in 1:nrounds
        opt = Optim.optimize(f_opt, x, optfunc , options; autodiff)
        if isa(optim_out, Vector)
            push!(optim_out, opt)
        end
        best = opt.minimizer
        val = fixed_f(best)
        x = mapin(best)
    end

    return val, x, x0
end

function optim_wrap(sense::Symbol, f::Function, gen::Function, mapin::Function=identity;
    nrounds::Int=1,
    n_starts::Int=1,
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    optim_out = nothing, 
    seed = -1)

    sense = sensemap(sense)

    if seed != -1
        Random.seed!(seed)
    end

    if n_starts > 1
        if sense == :Max
            bestval = -Inf
            comp = >
        else
            bestval = Inf
            comp = <
        end

        x0 = gen()
        val = f(x)
        bestval = val
        for i in 2:n_starts
            x = gen()
            val = f(x)
            if comp(val, bestval)
                bestval = val
                x0 = x
            end
        end        
    else
        x0 = gen()
    end

    optim_wrap(sense, f, x0, mapin;
            nrounds,
            optfunc,
            options,
            autodiff,
            optim_out)
end

optim_wrap(sense::typeof(min), obj::Function, args...; kwargs...) = optim_wrap(:Min, obj, args...; kwargs...)
optim_wrap(sense::typeof(max), obj::Function, args...; kwargs...) = optim_wrap(:Max, obj, args...; kwargs...)


function optim_wrap_sub(sense, f::Function, gen::Function, mapin=identity; 
        t_lim = Inf,
        n_trials = Inf,
        nrounds = 1,
        n_starts = 1,
        file_base = "",
        verbose = false,
        verbosity = 1 + verbose,
        seed = -1,
        optfunc=NelderMead(),
        autodiff = :finite,
        options = Optim.Options(),
        record = nothing,
        report_checks = [1.01],
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

    iters = 0
    n_converged = 0

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

    # # BIG WARNING! When the dimension of the problem is small, usually the first round takes up a lot more time than the other ones, so this is wasteful
    # if nrounds > 1
    #     t_lim /= nrounds
    #     n_trials /= nrounds
    # end

    rep = []
    t_checks = t_lim .* report_checks
    it = 1
    
    t0 = t1 = time()
    t_stop = t0 + t_lim

    i = 0

    n_converged = 0

    while (time() < t_stop && i < n_trials && comp(stop_val, bestval))

        t1 = time() - t0

        if it <= length(t_checks) && t1 > t_checks[it]
            push!(rep, [bestval,t1])
            it += 1
        end

        tdo = Dict(fn=>getfield(options, fn) for fn ∈ fieldnames(typeof(options)))
        tdo[:time_limit] = t_stop - time()
        options = Optim.Options(;tdo...)

        optim_out = []

        a = optim_wrap(sense, f, gen, mapin;
            nrounds,
            n_starts,
            optfunc,
            options,
            autodiff,
            optim_out,
            seed)

        # Dictionary recording is cleaner for single process, might have issues for parallel processes (i.e. updates at different times)
        # if isa(record, Dict) 
        #     "val" in keys(record) && push!(keys["val"], a[1])
        #     "xopt" in keys(record) && push!(keys["xopt"], a[2])
        #     "x0" in keys(record) && push!(keys["x0"], a[3])
        #     "conv" in keys(record) && push!(keys["conv"], Optim.converged(optim_out[end]))
        # end

        isa(record, Vector) && push!(record, [a..., Optim.converged(optim_out[end])]) 

        i += 1
        n_converged += Optim.converged(optim_out[end])

        val = first_number(a)

        if comp(val,bestval)
            bestval = val
            besta = a
            push!(bests,a)
            if verbosity >= 2
		        # report(i, bestval, besta, txt_file) # This function foes not work anymore! Not sure where it comes from...
            end
            !isempty(file_base) && save(jld_file, "bests", bests)
        elseif verbosity > 2
            daslog("iteration: $(i), val: $(val)")
        end
    end

    # rep != [] && push!(rep, [bestval,time()-t0]) # JUST IN CASE THE LAST VALUE IS FOUND IN THE LAST ITERATION, COMMENT TO SKIP THIS

    if verbosity > 0
        daslog("Ran for $(i) iterations (converged on $(n_converged)) and $(time()-t0) seconds. Val: $(first_number(besta))")
    end

    iters = i

    return besta[1], besta[2], iters, n_converged, rep
end

function optim_wrap_main(sense, f::Function, gen::Function, mapin=identity; 
        t_lim = Inf,
        n_trials = Inf,
        procs = 0,
        nrounds = 1,
        n_starts = 0,
        file_base = "",
        verbose = false,
        verbosity = 1 + verbose,
        seed = -1,
        optfunc=NelderMead(),
        autodiff = :finite,
        options = Optim.Options(),
        record = nothing,
        report_checks = [1.01],
        report_iters = nothing,
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

    if t_lim == Inf && n_trials == Inf
        @warn "No budget set, just running once"
        x0 = gen()

        val, x, _ = optim_wrap(sense, obj, x0, mapin;
            nrounds,
            optfunc,
            options,
            autodiff,
            optim_out)
        return val, x
    end

    parallel = isdefined(Main, :nprocs) && nprocs() > 1 && procs > 1

    sub_verbosity = max(0,verbosity-1)

    if parallel
        sub = j->optim_wrap_sub(sense, f, gen, mapin; 
            t_lim,
            n_trials,
            nrounds, 
            n_starts,
            file_base,
            verbosity = sub_verbosity, 
            seed,
            optfunc,
            autodiff,
            options,
            record,
            report_checks,
            thisid = j,
            stop_val)
    else
        sub = ()->optim_wrap_sub(sense, f, gen, mapin; 
            t_lim,
            n_trials,
            nrounds, 
            n_starts,
            file_base,
            verbosity = sub_verbosity, 
            seed,
            optfunc,
            autodiff,
            options,
            record,
            report_checks,
            thisid = 1,
            stop_val)
    end

    t0 = time()

    iters = 0
    n_converged = 0

    if !parallel
        a = sub()
        rep = a[end]
        n_converged = a[end-1]
        iters = a[end-2]
        a = a[1:(end-3)]
    else    
        keepbest(a,b) = comp(first_number(a), first_number(b)) ? a : b
        add_iters(a,b) = a[end-1:end] .+ b[end-1:end]
        keepbest_additers(a,b) = ((comp(first_number(a), first_number(b)) ? a[1:end-2] : b[1:end-2])..., add_iters(a,b)...)
        
        outputs = pmap(j->sub(j), 2:(1+procs))

        outputs1 = [out[1:end-1] for out in outputs]
        reps = sort(vcat([out[end] for out in outputs]...), by=x->x[2]) #sorting is inefficient, but shouldn't make a difference for reasonably large report_fac

        a = reduce(keepbest_additers, outputs1)
        rep = clean_merged_reports(reps, procs, sense)
        iters = a[end-1]
        n_converged = a[end]
        a = a[1:(end-2)]
    end

    isa(report_iters, Vector) && push!(report_iters, [iters, n_converged]...)

    if verbosity > 0
        if verbosity == 1
            daslo("Ran for $(time()-t0) seconds and $iters total iters (converged $(n_converged)). ")
        end
        daslog("Val: $(a[1])")

        rep != [] && daslo("Intermediate progress:")
        if length(rep) < 3 # still need to test this!
            for r in rep
                daslo(" found value $(r[1]) after $(round(r[2], digits=2))s")
            end
        else
            for r in rep
                daslog("time: $(round(r[2], digits=2))s, val: $(r[1])")
            end
        end
#        println("$(a[2])")
#        println("Val: $(a[1])")
    end

    return a

end


function clean_merged_reports(reports, procs, sense)
    sense == :Max ? (extremum = argmax) : (extremum = argmin)
    out = []
    p = 1
    vals = [rep[1] for rep in reports]
    times = [rep[2] for rep in reports]
    while p < length(reports)
        best = extremum(vals[p:p+procs-1])
        push!(out, [vals[p+best-1], times[p+best-1]])
        p += procs
    end
    out
end