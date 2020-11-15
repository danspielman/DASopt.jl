# a variant of a go-with-the-winner's algorithm


"""
x, val = function gowin(f, pop, improver; mapin = identity,
            sense = :Max,
            t_lim = Inf,
            n_rounds = Inf,
            conv_tol = 1e-7,
            verbosity = 1,
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

Example improver:
`improver(x) = randline(f, x, mapin, sense=:Min, max_its = 10)[1]`
"""
function gowin(f, pop, improver; mapin = identity,
    sense = :Max,
    t_lim = Inf,
    n_rounds = Inf,
    conv_tol = 1e-7,
    verbosity = 1)

    @assert !(parallel && threads)
    @assert sense==:Max || sense==:Min

    serial = !(parallel || threads)

    if sense == :Max
        bestimum = maximum
        comp = >
    else
        bestimum = minimum
        comp = <
    end

    t_stop = time() + t_lim
    its = 0

    t0 = time()

    vals = f.(pop)

    while time() < t_stop && 
        its < n_rounds &&
        conv_test(pop) > conv_tol

        if verbosity > 1
            println("Round $(its), Time $(time()-t0) : best: $(bestimum(vals)), median: $(median(vals))")
        end

        its += 1

        if serial
            newpop = improver.(pop)
            vals = f.(newpop)
        end

        if parallel
            newpop = pmap(improver,pop)
            vals = pmap(f,newpop)
        end

        if threads 
            newpop = ThreadsX.map(improver,pop)
            vals = ThreadsX.map(f,newpop)           
        end
        

        med = median(vals)

        bestpop = newpop[comp.(vals, med)]

        pop = vcat(bestpop, bestpop)

    end

    vals = f.(pop)

    i = argmax(vals)
    x = pop[i]
    val = vals[i]

    if verbosity > 0
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


