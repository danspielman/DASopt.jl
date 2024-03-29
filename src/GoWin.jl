# a variant of a go-with-the-winner's algorithm


"""
    x, val = gowin(f, pop, improver; mapin = identity,
            sense = :Max,
            t_lim = Inf,
            n_rounds = Inf,
            conv_tol = 1e-7,
            verbosity = 1,
            keepon = false,
            threads = false,
            parallel = false)
        
A variant of a go with the winner's algorithm.
Begins with an initial population.
Runs an `improver` on each element of the population.
Then, discards the bottom performing half, replicates the top half,
and keeps going.  

Only one of parallel or threads can be true.

Keeps going for either n_rounds, or until t_lim is hit.
Also stops if all samples in the population are within conv_tol relative distance from each other.
If it detects convergence and `keepon` is `true`, then it restarts with the initial population.

Example improver:
`improver(x) = randline(f, x, mapin, sense=:Min, max_its = 10)[1]`
"""
function gowin(f, pop, improver; mapin = identity,
    sense = :Max,
    t_lim = Inf,
    n_rounds = Inf,
    conv_tol = 1e-7,
    verbosity = 1,
    keepon = false,
    parallel = false,
    threads = false)

    @assert !(parallel && threads)
    @assert sense==:Max || sense==:Min

    if t_lim == Inf && keepon == true
        error("If you set keepon = true and t_lim = Inf this will run forever")
    end

    if sense == :Max
        bestimum = maximum
        comp = >=
        bestval = -Inf
    else
        bestimum = minimum
        comp = <=
        bestval = Inf
    end

    n_keepons = 0

    init_pop = copy(pop)

    t_stop = time() + t_lim

    t0 = time()

    time_per_rerun = 0.0

    x = nothing

    while time() + time_per_rerun < t_stop

        pop = copy(init_pop)

        new_x, new_val = gowin_inner(f, pop, improver;
            mapin, sense, t_lim, n_rounds, conv_tol, verbosity, 
            keepong, parallel, threads)

            if comp(new_val, bestval)
                bestval = new_val
                x = new_x
            end

        n_keepons += 1
        time_per_rerun = (time() - t0) / n_keepons

    end

    if verbosity > 0 && n_keepons > 1
        println("Restarted the process $(n_keepons) times.")
    end

    return x, val

end

function gowin_inner(f, pop, improver; mapin = identity,
    sense = :Max,
    t_lim = Inf,
    n_rounds = Inf,
    conv_tol = 1e-7,
    verbosity = 1,
    keepon = false,
    parallel = false,
    threads = false)

    serial = !(parallel || threads)

    if sense == :Max
        bestimum = maximum
        comp = >=
        bestval = -Inf
    else
        bestimum = minimum
        comp = <=
        bestval = Inf
    end


    t_stop = time() + t_lim
    its = 0

    t0 = time()

    pop = mapin.(pop)

    vals = f.(pop)
    newpop = copy(pop)

    function improve(p, v)
        newi = mapin(improver(p))
        vi = f(newi)
        
        if !comp(vi, v) 
            # recompute original
            vorig = f(p)
            if !comp(vi, vorig)
                vi = vorig
                newi = p
            end
        end   
        return newi, vi 
    end

    while time() < t_stop && 
        its < n_rounds &&
        conv_test(pop) > conv_tol

        if verbosity > 1
            println("Round $(its), Time $(time()-t0) : best: $(bestimum(vals)), median: $(median(vals))")
        end

        its += 1

        if serial
            news = map(zip(pop,vals)) do (p,v)
                improve(p,v)
            end
            #newpop = mapin.(improver.(pop))
            #vals = f.(newpop)
        end

        if parallel
            news = pmap(zip(pop,vals)) do (p,v)
                improve(p,v)
            end
        end
        
        if threads # need to make this work with improvei
            news = ThreadsX.map(zip(pop,vals)) do (p,v)
                improve(p,v)
            end      
        end
        
        vals = [new[2] for new in news]
        newpop = [new[1] for new in news] 

        med = median(vals)

        bestpop = newpop[comp.(vals, med)]

        pop = vcat(bestpop, bestpop)

    end

    vals = f.(pop)

    if sense == :Max
        i = argmax(vals)
    else
        i = argmin(vals)
    end

    x = pop[i]
    val = vals[i]

    if verbosity > 0
        println(x)

        println("Best value is $(val).")
        
        if time() > t_stop
            println("Met time limit")
        end

        if its >= n_rounds
            println("Reached round limit.")
        end

    end

    return x, val
end

function conv_test(pop)
    x0 = pop[1]
    nx0 = norm(x0)

    return maximum(norm(x0 - p)/(nx0 + norm(p)) for p in pop)
end


