
randline(sense::typeof(min), obj::Function, args...; kwargs...) = randline(:Min, obj, args...; kwargs...)
randline(sense::typeof(max), obj::Function, args...; kwargs...) = randline(:Max, obj, args...; kwargs...)

randline(sense::Symbol, f::Function, x0, mapin = identity; 
    t_lim = Inf,
    max_its = Inf,
    verbosity = 0,
    tol = 1e-7
) = randline(f, x0, mapin; 
    tol, t_lim, max_its, sense, verbosity)    



"""
    val, x = randline(f, x0, mapin; 
        tol = 1e-7,
        t_lim = Inf,
        max_its = 10 n log n (if t_lim not set. o/w is Inf)
        sense = :Max,
        verbosity = 0)

Optimize by performing linesearches in random directions, which are sparse with probability 1/2.
Stops when make less than tol progress for length(x0) iterations in a row,
or after t_lim seconds.

Is unlikely to beat other techniques unless it is really important to work
in the space obtained by applying mapin.
"""
function randline(f::Function, x0, mapin;
    tol = 1e-7,
    t_lim = Inf,
    max_its = Inf,
    sense = :Max,
    verbosity = 0)

    sense = sensemap(sense)

    @assert sense==:Max || sense==:Min

    if t_lim == Inf && max_its == Inf
        max_its = round(Int, 10*length(x0)*log(length(x0)))
        verbosity > 1 && println("because max_its and t_lim Inf, set max_its to $(max_its)")
    end

    if sense == :Max
        sgn = -1
        comp = >
    else
         sgn = 1
        comp = <
    end

    x = mapin(x0)
    n = length(x)
    max_stag = max(n,10)


    t0 = time()
    stag_rounds = 0

    val = f(x)
    
    # if go max_stag iters with t < sizet/4, then halve it
    sizet = 1.0
    num_small_t = 0

    iters = 0
    while (time() - t0 < t_lim) && stag_rounds < max_stag && iters < max_its
        iters += 1

        del = randn(size(x)...)

        # with prob 1/2, mask to make it sparse
        if rand() < 1/2
            r = rand(size(x)...)
            mask = r .<= 2*minimum(r)
            del .*= mask
        end

        del = del * norm(x) / norm(del)

        opt = optimize(t->sgn*f(mapin(x + t*del)), -2*sizet, 2*sizet, Brent(), iterations = 10)
        t = opt.minimizer
        newval = sgn*opt.minimum

        if abs(t) < sizet / 4
            num_small_t += 1
            if num_small_t >= max_stag
                sizet /= 2
                num_small_t = 0
                verbosity > 1 && println("sizet: $(sizet)")
            end
        else
            if sizet < 1 && abs(t) > sizet 
                sizet *= 2
                num_small_t = 0
                verbosity > 1 && println("sizet: $(sizet)")
            end
        end

        if comp(newval,val)
            if abs(newval - val) < tol
                stag_rounds += 1
            else
                stag_rounds = 0
            end
            val = newval
            x = mapin(x + t*del)

            verbosity > 1 && println("val: $(val)")
        end
    end

    if verbosity > 0 
        if stag_rounds >= n
            println("Stopped making improvement. Ran for $(iters) iterations.")
        end

        if iters >= max_its
            println("Reached max_its.")
        end
        if time() > t_lim
            println("Time up. Ran for $(iters) iterations.")
        end
    end

    return val, x

end

const golden_ratio = (sqrt(5) + 1) / 2

"""
    x = golden(f, a, b, its)

Minimum of f between a and b. Runs for a fixed number of iterations, `its`.
"""
function golden(f, a, b, its)
    
    it = 0
    
    while it < its
        
        c = b - (b - a) / golden_ratio
        d = a + (b - a) / golden_ratio
        
        it += 1
        if f(c) < f(d)
            b = d
        else
            a = c
        end
    
    end
    
    return (a+b)/2
end

function golden2(f, x0, del, a, b, its)
    
    it = 0
    
    while it < its
        
        c = b - (b - a) / golden_ratio
        d = a + (b - a) / golden_ratio
        
        it += 1
        if f(x0 + c*del) < f(x0 + d*del)
            b = d
        else
            a = c
        end
    
    end
    
    return (a+b)/2
end