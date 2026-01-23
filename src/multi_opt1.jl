# multi_opt

#=

A combination of optimization algorithms.

=#

using DASopt, Optim, LineSearches

include("optim_wrap1.jl")

safeintdiv(a,b) = a == Inf ? Inf : a ÷ b

function multi_opt(sense, f::Function, gen::Function, mapin=identity; t_lim = 0,
    procs = 0,
    verbosity = 0,
    t_lims=Dict("NM"=>1/3, "LBFGS"=>1/3, "Popevolve"=>1/3),
    stop_val = sensemap(sense) == :Max ? Inf : -Inf)

    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    sub_verbosity = verbosity 
    best_alg = ""

    report_iters = []

    t_lim_NM = t_lim_LBFGS = t_lim_pop = 0

    for alg in keys(t_lims)
        if lowercase(alg) == "nm"
            t_lim_NM = t_lims[alg] * t_lim / 2
        elseif lowercase(alg) == "lbfgs"
            t_lim_LBFGS = t_lims[alg] * t_lim / 2
        elseif lowercase(alg) == "popevolve"
            t_lim_pop = t_lims[alg] * t_lim 
        else
            @warn "Key $alg invalid, please provide a valid optimization algorithm"
        end
    end
    
    t0 = time()

    # NelderMead

    nrounds = mapin==identity ? 1 : 2

    # if verbosity > 0
    #     daslog("Time limits: NM=$t_lim_NM, LBFGS=$t_lim_LBFGS, Popevolve=$t_lim_pop")
    #     daslog()
    # end

    verbosity > 0 && daslo("NM. ")
    val, x = optim_wrap_main(sense, f, gen, mapin; 
        t_lim = t_lim_NM, nrounds, procs, verbosity=sub_verbosity,
        report_iters, stop_val)

    bestval = val
    bestx = copy(x)
    bestalg = "NM"

    best_NM = [-stop_val, 0, 1, 1] # [value, time, fac_iters, fac_nrounds]

    n_iters = report_iters[1]
    n_converged = report_iters[2]
    fac_iters = fac_nrounds = 1

    t_lim2 = t_lim_NM

    while t_lim2 > 1e-2
        report_iters = []
        t_iter = time()

        if (n_iters > 10*(procs+1)) && (n_converged < 0.1 * n_iters) #not enough converged
            t_lim2 /= 2

            more_iters = rand() < 0.5 #choose whether to increase nrounds or Optim inner iterations

            if more_iters
                fac_iters *= 10
                verbosity > 0 && daslo("NM_it$(fac_iters)nr$(fac_nrounds). ")
                val, x = optim_wrap_main(sense, f, gen, mapin; 
                    t_lim = t_lim2, procs, verbosity=sub_verbosity,
                    report_iters, stop_val,
                    nrounds = fac_nrounds * nrounds,
                    options = Optim.Options(iterations=round(Int, fac_iters*1_000)))
            else
                fac_nrounds *= 2
                verbosity > 0 && daslo("NM_it$(fac_iters)nr$(fac_nrounds). ")
                val, x = optim_wrap_main(sense, f, gen, mapin; 
                    t_lim = t_lim2, procs, verbosity=sub_verbosity,
                    report_iters, stop_val,
                    nrounds = fac_nrounds * nrounds,
                    options = Optim.Options(iterations=round(Int, fac_iters*1_000)))
            end

        elseif (n_iters > 10*(procs+1)) && (n_converged > 0.7 * n_iters)
            t_lim2 /= 2
            fac_iters /= 2
            fac_nrounds = max(2, fac_nrounds ÷ 2)
            verbosity > 0 && daslo("NM_it$(fac_iters)nr$(fac_nrounds). ")
            val, x = optim_wrap_main(sense, f, gen, mapin; 
                t_lim = t_lim2, procs, verbosity=sub_verbosity,
                report_iters, stop_val,
                nrounds = fac_nrounds * nrounds,
                options = Optim.Options(iterations=round(Int, fac_iters*1_000)))
        else
            val, x = optim_wrap_main(sense, f, gen, mapin; 
                t_lim = t_lim2, procs, verbosity=sub_verbosity,
                report_iters, stop_val,
                nrounds = fac_nrounds * nrounds,
                options = Optim.Options(iterations=round(Int, fac_iters*1_000)))

            t_lim2 = 0
        end

        if comp(val, bestval)
            bestval = val
            bestx = copy(x)
            bestalg = "NM_it$(fac_iters)nr$(fac_nrounds)"
        end

        if comp(val, best_NM[1])
            best_NM = [val, time()-t_iter, fac_iters, fac_nrounds]
        end

        n_iters = report_iters[1]
        n_converged = report_iters[2]

    end

    verbosity == 0 && daslog("Best NM found value $(best_NM[1]) in $(round(best_NM[2],digits=3)) seconds (iters=$(round(Int, best_NM[3]*1_000)), nrounds=$(round(Int, best_NM[4])*nrounds))")

    # LBFGS

    verbosity > 0 && daslo("\nLBFGS. ")
    val, x = optim_wrap_main(sense, f, gen, mapin; 
        t_lim = t_lim_LBFGS, nrounds, procs, verbosity=sub_verbosity,
        report_iters, stop_val,
        optfunc = LBFGS(;linesearch = LineSearches.BackTracking()))

    if comp(val, bestval)
        bestval = val
        bestx = copy(x)
        bestalg = "LBFGS"
    end

    best_LBFGS = [-stop_val, 0, 1, 1] # [value, time, fac_iters, fac_nrounds]

    n_iters = report_iters[1]
    n_converged = report_iters[2]
    fac_iters = fac_nrounds = 1
    t_lim2 = t_lim_LBFGS

    while t_lim2 > 1e-2
        report_iters = []
        t_iter = time()

        if (n_iters > 10*(procs+1)) && (n_converged < 0.1 * n_iters) #not enough converged
            t_lim2 /= 2

            more_iters = rand() < 0.5 #choose whether to increase nrounds or Optim inner iterations

            if more_iters
                fac_iters *= 10
                verbosity > 0 && daslo("LBFGS_it$(fac_iters)nr$(fac_nrounds). ")
                val, x = optim_wrap_main(sense, f, gen, mapin; 
                    t_lim = t_lim2, procs, verbosity=sub_verbosity,
                    report_iters, stop_val,
                    optfunc = LBFGS(;linesearch = LineSearches.BackTracking()),
                    nrounds = fac_nrounds * nrounds,
                    options = Optim.Options(iterations=round(Int, fac_iters*1_000)))
            else
                fac_nrounds *= 2
                verbosity > 0 && daslo("LBFGS_it$(fac_iters)nr$(fac_nrounds). ")
                val, x = optim_wrap_main(sense, f, gen, mapin; 
                    t_lim = t_lim2, procs, verbosity=sub_verbosity,
                    report_iters, stop_val,
                    optfunc = LBFGS(;linesearch = LineSearches.BackTracking()),
                    nrounds = fac_nrounds * nrounds,
                    options = Optim.Options(iterations=round(Int, fac_iters*1_000)))
            end

        elseif (n_iters > 10*(procs+1)) && (n_converged > 0.7 * n_iters)
            t_lim2 /= 2
            fac_iters /= 2
            fac_nrounds = max(2, fac_nrounds ÷ 2)
            verbosity > 0 && daslo("LBFGS_it$(fac_iters)nr$(fac_nrounds). ")
            val, x = optim_wrap_main(sense, f, gen, mapin; 
                t_lim = t_lim2, procs, verbosity=sub_verbosity,
                report_iters, stop_val,
                optfunc = LBFGS(;linesearch = LineSearches.BackTracking()),
                nrounds = fac_nrounds * nrounds,
                options = Optim.Options(iterations=round(Int, fac_iters*1_000)))
        else
            val, x = optim_wrap_main(sense, f, gen, mapin; 
                t_lim = t_lim2, procs, verbosity=sub_verbosity,
                report_iters, stop_val,
                optfunc = LBFGS(;linesearch = LineSearches.BackTracking()),
                nrounds = fac_nrounds * nrounds,
                options = Optim.Options(iterations=round(Int, fac_iters*1_000)))

            t_lim2 = 0
        end

        if comp(val, bestval)
            bestval = val
            bestx = copy(x)
            bestalg = "LBFGS_it$(fac_iters)nr$(fac_nrounds)"
        end

        if comp(val, best_LBFGS[1])
            best_LBFGS = [val, time()-t_iter, fac_iters, fac_nrounds]
        end

        n_iters = report_iters[1]
        n_converged = report_iters[2]

    end

    verbosity == 0 && daslog("Best LBFGS found value $(best_LBFGS[1]) in $(round(best_LBFGS[2],digits=3)) seconds (iters=$(round(Int, best_LBFGS[3]*1_000)), nrounds=$(round(Int, best_LBFGS[4])*nrounds))")
    
    # popevolve

    verbosity == 0 && daslo("Popevolve. ")
    val, x = popevolve(sense, f, gen, mapin; 
    t_lim = t_lim_pop, verbosity=sub_verbosity+1, stop_val, randline = 4,
    procs
    )

    if comp(val, bestval)
        bestval = val
        bestx = copy(x)
        bestalg = "Popevolve"
    end


    if verbosity == 0
        daslo("\nRan for $(time()-t0) seconds. Best alg: $(bestalg). ")
    end
    daslog("Val: $bestval")

    return bestval, bestx

end