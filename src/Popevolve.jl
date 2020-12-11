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

The return, opt, has a couple of fields:
* best: the best solution
* bestval: the value of it
* pop: the population at the end

"""
function popevolve(f::Function, x0::AbstractArray{Float64}, t_lim;
    mapin = identity,
    sense = :Max,
    n_fac = 10, 
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false
)

    n = n_fac*length(x0)
    pop = [mapin(randn(size(x0))) for i in 1:n]

    popevolve(f, pop, t_lim; verbosity, mapin, sense, threads, conv_tol)

end

function popevolve(f::Function, pop::AbstractArray{Array{T,N},1}, t_lim;
    mapin=identity,
    sense = :Max,
    conv_tol = 1e-6,
    verbosity = 1,
    threads = false    
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


    n = length(pop)

    verbose && println("initial pop size $(n).")

    vals = f.(pop)

    t0 = time()

    verbose && println("initial best: $(minimum(vals))")

    t1 = time()

    its = 0

    round = 0

    while (time() < t0 + t_lim)
        if time() > t1 + t_lim/9
            verbose && println("$(minimum(vals))")
            t1 = time()
        end

        round += 1
        pe = randperm(n)

        if threads
            Threads.@threads for k in pe
                i = rand(1:n)
                j = i
                while j == i
                    j = rand(1:n)
                end

                del = pop[i] - pop[j]
                opt = optimize(t->sgn*f(mapin(pop[k] + t*del)), -2, 2, Brent(), iterations = 10)
                t = opt.minimizer
                bestval = sgn*opt.minimum
                if comp(bestval, vals[k])
                    vals[k] = bestval
                    pop[k] = mapin(pop[k] + t*del)
                end
            end
        else
            for k in pe
                i = rand(1:n)
                j = i
                while j == i
                    j = rand(1:n)
                end

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

        best = bestimum(vals)
        worst = worstimum(vals)

        if verbosity == 2
            println("Round $(round): best: $(best), worst: $(worst).")
        end

        if abs(best - worst) < conv_tol
            break
        end
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
