#=

These are optimizers, and wrappers for them, that I like to use.

=#

"""
    opt = popevolve(f, x0, t_lim; mapin = identity,
        sense = :Max,
        n_fac = 10, 
        conv_tol = 1e-6,
        verbosity = 1,
        threads = false
    )

Generates and evolves a population of potential solutions to minimize the function f.

# Arguments
- `x0` is either an example input, and an initial population is generated to look like this. Or it is just the initial population.
- `n_fac::Integer`: if `x0` is an example rather than a population, the number of elements in the initial population is this times the length of `x0`. 
- `t_lim`: un upper bound on the number of seconds for which to run
- `sense`: either `:Max` or `:Min`, default is `:Max`
- `mapin`: a function to apply to map inputs into the domain
- `conv_tol`: stop once all solutions are within this distance in function value
- `threads`: if true use multithreading (not yet working)
- `parallel`: if true use pmap. most useful when `f` is slow
- `randline`: if not infinite, will search in a random direction every randline steps, instead of the DE one.

The return, opt, has a couple of fields:
* best: the best solution
* bestval: the value of it
* pop: the population at the end
* 

"""
function popevolve(f::Function, x0::AbstractArray{Float64}, t_lim;
    mapin = identity,
    sense = :Max,
    n_fac = 10, 
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false,
    parallel = false,
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf
)
    @assert !(parallel && threads)

    n = n_fac*length(x0)
    pop = [mapin(randn(size(x0))) for i in 1:n]

    popevolve(f, pop, t_lim; verbosity, mapin, sense, threads, parallel, conv_tol, randline, stop_val)

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

function popevolve(f::Function, pop::AbstractArray{Array{T,N},1}, t_lim;
    mapin=identity,
    sense = :Max,
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false,
    parallel = false,
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf
    ) where {T,N}

    @assert !(parallel && threads)

    if parallel
        return popevolve_par(f, pop, t_lim; 
        mapin, sense, conv_tol, randline, verbosity, stop_val)
    end

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

    verbose && println("initial pop size $(n).")

    vals = f.(pop)

    t0 = time()

    bestval = bestimum(vals)
    verbose && println("initial best: $(bestval)")

    t1 = time()
    round = 0

    while time() < t0 + t_lim && comp(stop_val, bestval)
        if time() > t1 + t_lim/9
            verbose && println("Round $(round): $(bestimum(vals))")
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
                i = ip[k]
                j = jp[k]
                if i != j

                    del = pop[i] - pop[j]


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

        if verbosity == 2
            println("Round $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end
    end

    i = argbest(vals)
    opt = (best=pop[i], bestval=vals[i], pop=pop, rounds=round, secs=time()-t0)

    verbose && println("final: $(vals[i]), after $(round) rounds.")

    return opt

end


function popevolve_par(f::Function, pop::AbstractArray{Array{T,N},1}, t_lim;
    mapin=identity,
    sense = :Max,
    conv_tol = 1e-6,
    verbosity = 1,
    randline = Inf,
    stop_val = sense == :Max ? Inf : -Inf
    ) where {T,N}

    verbose = verbosity > 0

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

    println("dev2 parallel")

    subfun(x) = sgn*f(mapin(x))

    n = length(pop)

    verbose && println("initial pop size $(n).")

    #vals = pmap(f,pop)
    vals = pmap(pop) do p
        try 
            f(p)
        catch jnk
            senseInf
        end
    end

    t0 = time()

    bestval = bestimum(vals)
    verbose && println("initial best: $(bestval)")

    t1 = time()

    round = 0

    while (time() < t0 + t_lim && comp(stop_val, bestval))
        if time() > t1 + t_lim/9
            verbose && println("Round $(round): $(bestimum(vals))")
            t1 = time()
        end

        round += 1

        ip = randperm(n)
        jp = randperm(n)

        dels = [pop[ip[k]] - pop[jp[k]] for k in 1:n]

        if iszero(mod(round, randline))
            verbosity == 2 && println("Random direction")
            dels = [(de = randn(size(x)); de*norm(x)/norm(de)) for x in dels]
        end

        pairs = pmap(zip(pop,dels)) do (p,del)
            if norm(del) < 1e-15
               return p, f(mapin(p)) 
            else
                bestval = NaN
                t = 0.0

                try
                    opt = optimize(t->sgn*f(mapin(p + t*del)), -2, 2, Brent(), iterations = 10)

                    t = opt.minimizer
                    bestval = sgn*opt.minimum

                    default = f(mapin(p))

                    if comp(bestval, default)
                        p = mapin(p + t*del)  
                    else
                        bestval = default
                    end
    
                catch err
                    println(err)
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

        if verbosity == 2
            println("Round $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end
    end

    i = argbest(vals)
    opt = (best=pop[i], bestval=vals[i], pop=pop, rounds=round, secs=time()-t0)
    verbose && println("final: $(vals[i]), after $(round) rounds.")
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
Recoomend pop size to be 2*dimension.

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

    verbose && println("initial best: $(minimum(vals))")

    t1 = time()
    round = 0

    counter = EveryN(n)

    while (time() < t0 + t_lim)
        if time() > t1 + t_lim/9
            verbose && println("Round $(round): $(bestimum(vals))")
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
            println("Iteration $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end

        round += 1
    end

    i = argbest(vals)
    opt = (best=pop[i], bestval=vals[i], pop=pop)

    verbose && println("final: $(vals[i]), after $(round) rounds.")

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
