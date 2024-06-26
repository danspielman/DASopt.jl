#=

These are optimizers, and wrappers for them, that I like to use.

=#

popevolve(sense::typeof(min), obj::Function, args...; kwargs...) = popevolve(:Min, obj, args...; kwargs...)
popevolve(sense::typeof(max), obj::Function, args...; kwargs...) = popevolve(:Max, obj, args...; kwargs...)


"""
    val, x = popevolve(sense, f, x0 / gen, mapin = identity; 
        t_lim = 60,
        n_fac = 10, 
        conv_tol = 1e-6,
        verbosity = 1,
        threads = false
    )

Generates and evolves a population of potential solutions to minimize the function f.

# Arguments
- `sense` should be `min` or `max`.
- `x0` is either an example input, and an initial population is generated to look like this. Or it is just the initial population.
- `gen` instead of `x0` we could give a generator
- `n_fac::Integer`: if `x0` is an example rather than a population, the number of elements in the initial population is this times the length of `x0`. 
- `t_lim`: un upper bound on the number of seconds for which to run
- `sense`: either `:Max` or `:Min`, default is `:Max`
- `mapin`: a function to apply to map inputs into the domain
- `conv_tol`: stop once all solutions are within this distance in function value
- `threads`: if true use multithreading (not yet working)
- `procs`: for parallel, number of procs to use
- `parallel`: if true use pmap. most useful when `f` is slow. will phase out and use procs instead
- `randline`: if not infinite, will search in a random direction every randline steps, instead of the DE one.
- `stop_val`: stop if get a value better than this

Returns the best value in `val`
and the vector on which it was obtained.
"""
function popevolve(sense::Symbol, f::Function, gen::Function, mapin = identity; 
    t_lim = -Inf,
    kwargs...
)
    if t_lim == -Inf
        verbosity > 0 && daslog("Setting t_lim is strongly recommended. It was just set to 60 seconds by default.")
        t_lim = 60
    end

    if sense == :max 
        sense = :Max
    end
    if sense == :min
        sense = :Min
    end

    popevolve(f, gen, t_lim; sense, mapin, kwargs...)
end

# this is the old interface and main entry point.
function popevolve(f::Function, gen::Function, t_lim;
    mapin = identity,
    sense = :Max,
    n_fac = 10, 
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false,
    parallel = false,
    procs = parallel ? nworkers() : 0, 
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf
)
    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    if procs > 0
        parallel = true
    end

    @assert !(parallel && threads)

    n = n_fac*length(gen())

    t0 = time()

    t_stop = t0 + t_lim

 
    besta = []

    nruns = 0
    totrounds = [0]

    while time() < t_stop
        nruns += 1

        if parallel 
            pool = WorkerPool(2:min(nprocs(), procs+1))
            pop = pmap(pool, 1:n) do _
                mapin(gen())                
            end
        else
            pop = [mapin(gen()) for i in 1:n] # could run too long
        end

        opt = popevolve_pop(f, pop, t_stop-time(); verbosity=max(0,verbosity-1),
         mapin, sense, threads, procs, conv_tol, randline, stop_val, totrounds)

        val = opt.bestval
        a = opt.best

        if comp(val,bestval)
            bestval = val
            besta = a
        end

    end

    if verbosity > 0
        t_tot = round(Int,time()-t0)
        daslog("Best val: $bestval, after $nruns runs with a total of $(totrounds[1]) rounds and $(t_tot) seconds")
    end

    return bestval, besta

end

const TRIES = [-2;-1;-0.5;0.5;1;2]

function try6(f::Function, mapin, x0, del, comp)
    bestt = TRIES[1]
    bestval = f(mapin(x0 + bestt*del))
    for i in 2:length(TRIES)
        t = TRIES[i]
        val = f(mapin(x0 + t*del))
        if comp(bestval, val)
            bestval = val
            bestt = t
        end
    end
    return bestt, bestval
end

# this is one of the main routines, it runs from a population.
function popevolve_pop(f::Function, pop::AbstractArray{Array{T,N},1}, t_lim;
    mapin=identity,
    sense = :Max,
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false,
    procs = 0,
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf,
    totrounds = []
    ) where {T,N}

    parallel = procs > 0

    @assert !(parallel && threads)

    if parallel
        return popevolve_par(f, pop, t_lim; procs,
        mapin, sense, conv_tol, randline, verbosity, stop_val, totrounds)
    end

    @assert sense==:Max || sense==:Min
    if sense == :Max
        bestimum = maximum
        worstimum = minimum
        argbest = argmax
        worst = -Inf
        comp = >=
        sgn = -1
    else
        bestimum = minimum
        worstimum = maximum
        argbest = argmin
        worst = Inf
        comp = <=
        sgn = 1
    end

    subfun(x) = sgn*f(mapin(x))

    n = length(pop)

    verbosity > 1 && daslog("initial pop size $(n).")

    t0 = time()

    vals = worst*ones(length(pop))
    for i in 1:length(pop)
        vals[i] = f(pop[i])
        if time() > t0 + t_lim
            verbosity > 0 && 
            daslog("hit t_lim before evaluating f on initial population.")    
            break
        end
    end
    # vals = f.(pop) # need to check time on this.

    bestval = bestimum(vals)
    verbosity > 1  && daslog("initial best: $(bestval)")

    t1 = time()
    round = 0

    while time() < t0 + t_lim && comp(stop_val, bestval)
        if time() > t1 + t_lim/9
            verbosity > 1 && daslog("Round $(round): $(bestimum(vals))")
            t1 = time()
        end

        round += 1

        ip = randperm(n)
        jp = randperm(n)

        if threads

            Threads.@threads for k in 1:n
                i = ip[k]
                j = jp[k]
                if i != j

                    del = pop[i] - pop[j]

                    # the following is faster, but not nearly as good, as brent's rule
                    # need an efficient, non-allocating, linesearch
                    # t, bestval = try6(f, mapin, pop[k], del, comp)
                    
                    opt = optimize(t->sgn*f(mapin(pop[k] + t*del)), -2, 2, Brent(), iterations = 10)
                    t = opt.minimizer
                    bestval = sgn*opt.minimum
                    
                    # t = golden2(subfun, pop[k], del, -2, 2, 5)
                    #bestval = f(mapin(pop[k] + t*del))
                    #bestval = sgn*opt.minimum
                    
                    if comp(bestval, vals[k])
                        vals[k] = bestval
                        pop[k] = mapin(pop[k] + t*del)  
                    end
                end
            end
        else
            for k in 1:n

                if time() > t0 + t_lim
                    break
                end

                i = ip[k]
                j = jp[k]
                if i != j

                    del = pop[i] - pop[j]

                    if iszero(mod(round, randline))
                        si = size(del)
                        de = randn(si...)
                        if rand() < 1/2
                            r = rand(si...)
                            mask = r .<= 2*minimum(r)
                            de .*= mask
                        end
                        del = de*norm(del)/norm(de)
                    end

                    opt = optimize(t->sgn*f(mapin(pop[k] + t*del)), -2, 2, Brent(), iterations = 10)
                    t = opt.minimizer
                    bestval = sgn*opt.minimum
                    if comp(bestval, vals[k])
                        vals[k] = bestval
                        pop[k] = mapin(pop[k] + t*del)
                    end
                end
            end
        end

        bestval = best = bestimum(vals)
        worst = worstimum(vals)

        if verbosity == 3
            daslog("Round $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end
    end

    i = argbest(vals)
    opt = (best=pop[i], bestval=vals[i], pop=pop, rounds=round, secs=time()-t0)

    verbosity > 0 && daslog("final: $(vals[i]), after $(round) rounds and $(time()-t0) seconds.")

    if length(totrounds) > 0
        totrounds[1] += round
    end

    return opt

end

# this is NOT a main routine -- it just works from an example
function popevolve(f::Function, x0::AbstractArray{Float64}, t_lim;
    mapin = identity,
    sense = :Max,
    n_fac = 10, 
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false,
    procs = 0,
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf
)

    if procs > 0
        parallel = true
    end

    @assert !(parallel && threads)

    n = n_fac*length(x0)

    sz = size(x0)

    if parallel 
        pool = WorkerPool(2:min(nprocs(), procs+1))
        pop = pmap(pool, 1:n) do _
            mapin(randn(sz))                
        end
    else
        pop = [mapin(randn(sz)) for i in 1:n] # could run too long
    end

    # pop = [mapin(randn(size(x0))) for i in 1:n]

    popevolve_pop(f, pop, t_lim; verbosity, mapin, sense, threads, procs, conv_tol, randline, stop_val)

end


function popevolve_par(f::Function, pop::AbstractArray{Array{T,N},1}, t_lim;
    mapin=identity,
    procs=0,
    sense = :Max,
    conv_tol = 1e-6,
    verbosity = 1,
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf,
    totrounds = []
    ) where {T,N}

    if procs == 0
        error("should not get to this code with procs = 0")
    end

    @assert sense==:Max || sense==:Min
    if sense == :Max
        bestimum = maximum
        worstimum = minimum
        argbest = argmax
        comp = >=
        sgn = -1
        senseInf = -Inf
    else
        bestimum = minimum
        worstimum = maximum
        argbest = argmin
        comp = <=
        sgn = 1
        senseInf = Inf
    end

    subfun(x) = sgn*f(mapin(x))

    n = length(pop)

    verbosity > 1 && daslog("initial pop size $(n).")

    t0 = time()
    t_stop = t0 + t_lim

    init_pop_computed = true

    #vals = pmap(f,pop)

    pool = WorkerPool(2:min(nprocs(), procs+1))

    vals = pmap(pool, pop) do p
        try 
            if time() < t_stop
                f(p)
            else
                init_pop_computed = false
                senseInf
            end
        catch jnk
            init_pop_computed = false
            senseInf
        end
    end

    verbosity > 0 && !init_pop_computed && daslog("hit t_lim before evaluating f on initial population. (in par)")    


    bestval = bestimum(vals)
    verbosity > 1 && daslog("initial best: $(bestval)")

    t1 = time()

    round = 0

    while (time() < t_stop && comp(stop_val, bestval))
        if time() > t1 + t_lim/9
            verbosity > 1 && daslog("Round $(round): $(bestimum(vals))")
            t1 = time()
        end

        round += 1

        ip = randperm(n)
        jp = randperm(n)

        dels = [pop[ip[k]] - pop[jp[k]] for k in 1:n]

        if iszero(mod(round, randline))
            verbosity == 3 && daslog("Random direction")
            for i in 1:length(dels)
                si = size(dels[i])
                del = randn(si...)
                if rand() < 1/2
                    r = rand(si...)
                    mask = r .<= 2*minimum(r)
                    del .*= mask
                end
                dels[i] = del*norm(dels[i])/norm(del)
            end

            #dels = [(de = randn(size(x)); de*norm(x)/norm(de)) for x in dels]
        end

        pairs = pmap(pool, zip(pop,dels)) do (p,del)
            if norm(del) < 1e-15
               return p, f(mapin(p)) 
            else
                bestval = NaN
                t = 0.0

                try
                    default = f(mapin(p))

                    if time() < t_stop
                        opt = optimize(t->sgn*f(mapin(p + t*del)), -2, 2, Brent(), iterations = 10)

                        t = opt.minimizer
                        bestval = sgn*opt.minimum

                        if comp(bestval, default)
                            p = mapin(p + t*del)  
                        else
                            bestval = default
                        end
                    else
                        bestval = default 
                    end
    
                catch err
                    daslog(err)
                end

                return p, bestval
            end
        end

        new_vals = [pair[2] for pair in pairs]

        ind = isfinite.(new_vals)
        vals[ind] .= new_vals[ind]
        for i in 1:n
            if ind[i]
                pop[i] = pairs[i][1]
            end
        end

        #pop = [pair[1] for pair in pairs]
        #vals = [pair[2] for pair in pairs]

        bestval = best = bestimum(vals)
        worst = worstimum(vals)

        if verbosity == 3
            daslog("Round $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end
    end

    i = argbest(vals)
    opt = (best=pop[i], bestval=vals[i], pop=pop, rounds=round, secs=time()-t0)
    verbosity > 0 && daslog("final: $(vals[i]), after $(round) rounds and $(time()-t0) seconds.")

    if length(totrounds) > 0
        totrounds[1] += round
    end

    return opt

end



"""
    opt = popnm(f, pop, t_lim; mapin = identity,
        sense = :Min,
        conv_tol = 1e-6,
        verbosity = 1,
        threads = false
    )

Generates and evolves a population of potential solutions to minimize the function f.
Following an approach like NelderMead, but with random choices.
Recommend pop size to be 2*dimension.

# Arguments
- `pop' is just the initial population.
- `t_lim`: un upper bound on the number of seconds for which to run
- `sense`: either `:Max` or `:Min`, default is `:Min`
- `mapin`: a function to apply to map inputs into the domain
- `conv_tol`: stop once all solutions are within this distance in function value

The return, opt, has a couple of fields:
* best: the best solution
* bestval: the value of it
* pop: the population at the end

"""
function popnm(f::Function, pop::AbstractArray{Array{T,N},1}, t_lim;
    mapin=identity,
    sense = :Min,
    conv_tol = 1e-6,
    verbosity = 1
    ) where {T,N}

    verbose = verbosity > 0

    @assert sense==:Max || sense==:Min
    if sense == :Max
        bestimum = maximum
        worstimum = minimum
        argbest = argmax
        comp = >=
        sgn = -1
    else
        bestimum = minimum
        worstimum = maximum
        argbest = argmin
        comp = <=
        sgn = 1
    end

    subfun(x) = sgn*f(mapin(x))

    n = length(pop)

    vals = f.(pop)

    t0 = time()

    verbose && daslog("initial best: $(minimum(vals))")

    t1 = time()
    round = 0

    counter = EveryN(n)

    while (time() < t0 + t_lim)
        if time() > t1 + t_lim/9
            verbose && daslog("Round $(round): $(bestimum(vals))")
            t1 = time()
        end

        center = mean(pop)
        

        k = rand(1:n)

        del = center - pop[k] 

        opt1 = optimize(t->sgn*f(mapin(pop[k] + t*del)), 1.5, 3, Brent(), iterations = 5)
        opt2 = optimize(t->sgn*f(mapin(pop[k] + t*del)), -1, -0.5, Brent(), iterations = 5)
        
        opt = comp(sgn*opt1.minimum, sgn*opt2.minimum) ? opt1 : opt2
        
        t = opt.minimizer
        bestval = sgn*opt.minimum
        if comp(bestval, vals[k])
            #=
            @show k, t, vals[k], bestval
            @show f(center), mean(vals)
            =#
            vals[k] = bestval
            pop[k] = mapin(pop[k] + t*del)
        end

        best = bestimum(vals)
        worst = worstimum(vals)

        if verbosity == 2 && counter() == 1
            daslog("Iteration $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end

        round += 1
    end

    i = argbest(vals)
    opt = (best=pop[i], bestval=vals[i], pop=pop)

    verbose && daslog("final: $(vals[i]), after $(round) rounds.")

    return opt

end

#=
"""
    x = constrained_min_norm(f, x0, t_lim)

f(x) = 0 defines the constraint
t_lim is in minutes
"""
function constrained_min_norm(f, x0, t_lim)

    t0 = time()

    fac = 0.5

    ma = copy(m0)
    for i in 1:10
    opt = optimize(m->ff_penalty2(m,d1,d2), ma, GradientDescent(), Optim.Options(f_tol=1e-2))
    mb1, mb2 = fix(opt.minimizer)
    println("step $(i), time $(opt.time_run), norm: $(norm(hcat(mb1,mb2)))")
    ma = opt.minimizer * 0.8
    end

end
=#
