"""
    x, val = randline(f, x0, mapin; 
        tol = 1e-7,
        t_lim = Inf,
        max_its = Inf,
        sense = :Max,
        verbosity = 0)

Optimize by performing linesearches in random directions.
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

    @assert sense==:Max || sense==:Min

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

        del = randn(size(x))
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

    return x, val

end

