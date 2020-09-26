#=

These are optimizers, and wrappers for them, that I like to use.

=#

"""
    opt = popevolve(f, x0, tlim; n_fac = 10, mapin = identity)

Generates and evolves a population of potential solutions to minimize the function f.

* n is the number of populations elements
* tlim the time limit in seconds

The return, opt, has a couple of fields:
* minimizer: the best solution
* minimum: the value of it
* pop: the population at the end

"""
function popevolve(f::Function, x0::AbstractArray{Float64}, tlim;
    n_fac = 5,
    verbose=true,
    mapin = identity)

    n = n_fac*length(x0)
    pop = [mapin(randn(size(x0))) for i in 1:n]

    popevolve(f, pop, tlim; verbose=verbose, mapin=mapin)

end

function popevolve(f::Function, pop::AbstractArray{Array{T,N},1}, tlim;
    verbose=true, mapin=identity) where {T,N}


    n = length(pop)

    verbose && println("initial pop size $(n).")

    vals = f.(pop)

    recs = []

    t0 = time()

    verbose && println("initial best: $(minimum(vals))")

    t1 = time()

    its = 0

    while (time() < t0 + tlim)
        if time() > t1 + tlim/9
            verbose && println("$(minimum(vals))")
            t1 = time()
        end

        its += 1

        i = rand(1:n)
        j = i
        while j == i
            j = rand(1:n)
        end
        k = rand(1:n)

        del = pop[i] - pop[j]
        opt = optimize(t->f(mapin(pop[k] + t*del)), -2, 2, Brent(), iterations = 10)
        t = opt.minimizer
        if opt.minimum < vals[k]
            push!(recs, opt.minimum)
            vals[k] = opt.minimum
            pop[k] = mapin(pop[k] + t*del)
        end
    end

    i = argmin(vals)
    opt = (minimizer=pop[i], minimum=vals[i], pop=pop, recs=recs)

    verbose && println("final: $(vals[i]), after $(its) iterations.")

    return opt

end

#=
"""
    x = constrained_min_norm(f, x0, tlim)

f(x) = 0 defines the constraint
tlim is in minutes
"""
function constrained_min_norm(f, x0, tlim)

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
