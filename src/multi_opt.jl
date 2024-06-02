# multi_opt

#=

A combination of optimization algorithms.

=#

using DASopt, Optim, LineSearches

function multi_opt(sense, f::Function, gen::Function, mapin=identity; t_lim = 0,
    procs = 0,
    verbosity = 1,
    stop_val = sensemap(sense) == :Max ? Inf : -Inf)

    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    sub_verbosity = max(0, verbosity-1)
    best_alg = ""

    report_iters = []
    report_converged = []
    
    t0 = time()

    # NelderMead

    nrounds = mapin==identity ? 1 : 2

    val, x = optim_wrap_tlim(sense, f, gen, mapin; 
        t_lim, procs, verbosity=sub_verbosity, stop_val,
        report_iters, report_converged, nrounds)

    bestval = val
    bestx = copy(x)
    bestalg = "NM"

    verbosity > 1 && daslog("NM : ", val)

    n_iters = report_iters[1]
    n_converged = report_converged[1]
    fac = 1

    t_lim2 = t_lim

    while (n_iters > 10*(procs+1)) && (n_converged < 0.1 * n_iters)
        fac *= 10
        t_lim2 /= 2

        report_iters = []
        report_converged = []

        val, x = optim_wrap_tlim(sense, f, gen, mapin; 
        t_lim2, procs, verbosity=sub_verbosity, stop_val,
        report_iters, report_converged, 
        nrounds, 
        options = Optim.Options(iterations=fac*1_000))

        if comp(val, bestval)
            bestval = val
            bestx = copy(x)
            bestalg = "NM_$fac"
        end

        verbosity > 1 && daslog("NM_$fac : ", val)

        n_iters = report_iters[1]
        n_converged = report_converged[1]

    end

    # LBFGS

    val, x = optim_wrap_tlim(sense, f, gen, mapin; 
        t_lim, procs, verbosity=sub_verbosity, stop_val,
        report_iters, report_converged,
        optfunc = LBFGS(;linesearch = LineSearches.BackTracking()))

    if comp(val, bestval)
        bestval = val
        bestx = copy(x)
        bestalg = "LBFGS"
    end
    
    verbosity > 1 && daslog("LBFGS : ", val)


    n_iters = report_iters[1]
    n_converged = report_converged[1]
    fac = 1
    t_lim2 = t_lim
    
    while (n_iters > 10*(procs+1)) && (n_converged < 0.1 * n_iters)
        fac *= 10
        t_lim2 /= 2


        report_iters = []
        report_converged = []

        val, x = optim_wrap_tlim(sense, f, gen, mapin; 
        t_lim2, procs, verbosity=sub_verbosity, stop_val,
        report_iters, report_converged, 
        options = Optim.Options(iterations=fac*1_000),
        optfunc = LBFGS(;linesearch = LineSearches.BackTracking())
        )

        if comp(val, bestval)
            bestval = val
            bestx = copy(x)
            bestalg = "LBFGS_$fac"
        end

        verbosity > 1 && daslog("LBFGS_$fac : ", val)

        n_iters = report_iters[1]
        n_converged = report_converged[1]

    end
    
    # popevolve

    val, x = popevolve(sense, f, gen, mapin; 
    t_lim, verbosity=sub_verbosity, stop_val, randline = 4,
    procs
    )

    if comp(val, bestval)
        bestval = val
        bestx = copy(x)
        bestalg = "Popevolve"
    end

    verbosity > 1 && daslog("Popevolve: ", val)


    if verbosity > 0
        if verbosity > 0
            daslo("Ran for $(time()-t0) seconds. Best alg: $(bestalg). ")
        end
        daslog("Val: $bestval")
#        daslog("$(a[2])")
#        daslog("Val: $(a[1])")
    end

    return bestval, bestx

end