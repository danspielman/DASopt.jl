# find_many.jl

"""
    goodsols, dists = find_many_0(sense, obj, gen, mapin=identity;
        fingerprint = identity,
        tol = 1e-6,
        t_lim = Inf, 
        optfunc=NelderMead(),
        options = Optim.Options(),
        autodiff = :finite,
        n_starts = 0,
        verbosity = 1
        )

This is the first of the find_many routines.
It just runs optim_wrap with the given parameters,
and returns all the solutions withing `tol` of the optimal.
It then sorts the solutions by a greedy procedures that maximizes distance from 
those that come before (in the fingerprint distance).
If `verbosity` > 0, it reports distance information.
"""
function find_many_0(sense, obj, gen, mapin=identity;
    fingerprint = identity,
    t_lim = Inf, 
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    n_starts = 0,
    verbosity = 1,
    tol = 1e-6
    )

    record = []
    _ = optim_wrap_tlim(sense, obj, gen, mapin;
        t_lim, 
        optfunc,
        options,
        autodiff,
        verbosity,
        n_starts,
        record 
        )

    bestval, comp, bestimum, argbest = bestfuns(sense)

    best = bestimum(r[1] for r in record)
    ind = findall(abs(r[1] - best) < tol*(1+abs(best) ) for r in record)

    daslog("Found $(length(ind)) solutions within $(tol*(1+abs(best) )) of $(best)")

    goodsol = record[ind]

    vecs = goodsol_to_vecs(sense, goodsol)

    vecs, dists = ordered_cover(vecs, tol; fingerprint)

    if verbosity > 0
        rad = 1.0
        while rad >= tol
            daslog("at distance $(rad) are $(1+sum(dists .>= rad)) distinct solutions")
            rad /= 10
        end
    end

    return vecs, dists

end

"""
    vecs = goodsol_to_vecs(sense, goodsol)

Put the best vec from goodsol first.
Then, put all the rest of the vecs from goodsol into vecs.
Note that it strips out the values that are in the first field of each tuple in goodsol.
"""
function goodsol_to_vecs(sense, goodsol)

    bestval, comp, bestimum, argbest = bestfuns(sense)

    i = argbest(r[1] for r in goodsol)
    vecs = [r[2] for r in goodsol[[i; 1:(i-1); (i+1):end]]]

    return vecs

end

"""
    vecs, dists = ordered_cover(invecs, radius=1e-3; fingerprint=identity)

vecs[1] is the vec in invecs[1].
After that, we find the furthest solution from vecs[1], and so on.
We order by distance from prev found solutions, and report the distances in `dists`
Discard any whose distances from those before is less than `radius`.
When radius is negative we order all solutions.
"""
function ordered_cover(invecs, radius=1e-3; fingerprint=identity)
    
    vecs = [invecs[1]]
    invecs = invecs[2:end]
    dists = []

    while !isempty(invecs)

        distprofile = [minimum(norm(fingerprint(v) - fingerprint(vec)) for vec in vecs) for v in invecs]

        bigval, bigind = findmax(distprofile)
        push!(dists, bigval)
        push!(vecs, invecs[bigind])

        distprofile[bigind] = -Inf
        ind = findall(distprofile .> radius)
        invecs = invecs[ind]

    end

    return vecs, dists
    
end

#=
function find_many_far(sense, obj, gen, mapin=identity;
    basesols = [],
    radius = 1e-3,
    fingerprint = identity,
    t_lim = Inf, 
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    n_starts = 0,
    verbosity = 1,
    tol = 1e-6
    )

    bestval, comp, bestimum, argbest = bestfuns(sense)

    if t_lim == 0
        @warn "t_lim should be set to something > 0"
        t_lim = 0.1
    end

    

    return vecs, dists

end
=#

function distance_penalty(x, vecs, fingerprint, radius)

    if isempty(vecs)
        return 0
    end

    r = minimum(norm(fingerprint(x) - fingerprint(vec)) for vec in vecs) 
    return r >= radius ? 0 : 1 / r - (1 / radius)
end

"""
Based on optim_wrap_tlim1_sub
Returns vecs, dists 
"""
function find_many_crude(sense, f::Function, gen, mapin=identity;
    fingerprint = identity,
    tol = 1e-6,
    t_lim = Inf, 
    optfunc=NelderMead(),
    options = Optim.Options(),
    autodiff = :finite,
    n_starts = 0,
    verbosity = 1
    )

    sense = sensemap(sense)
    bestval, comp, bestimum, argbest = bestfuns(sense)

    sgn = sense == :Min ? 1 : -1

    if t_lim == 0
        @warn "t_lim should be set to something > 0"
        t_lim = 0.1
    end

    t0 = time()
    t_stop = t0 + t_lim

    record = []
    vecs = []

    failcnt = 0

    i = 0
    while time() < t_stop
        i += 1

        tdo = Dict(fn=>getfield(options, fn) for fn ∈ fieldnames(typeof(options)))
        tdo[:time_limit] = t_stop - time()
        options = Optim.Options(;tdo...)

        a = optim_wrap(x->f(x) + sgn*distance_penalty(x, vecs, fingerprint, 1/(1+failcnt)), 
            gen, mapin;
        optfunc,
        sense,
        options,
        autodiff,
        n_starts)

        val = f(a[2])

        if comp(val,bestval)
            bestval = val
            ind = findall(abs(r[1] - bestval) < tol*(1+abs(bestval) ) for r in record)
            record = record[ind]
            vecs = [r[2] for r in record]
            
            #=
            if length(ind) == 0
                record = []
            else
                record = record[ind]
            end
            =#
        end


        if abs(val - bestval) < tol*(1+abs(bestval))
            push!(record, a)
            push!(vecs, a[2])
        else
            failcnt += 1
        end

        if verbosity > 2
            daslog("iteration: $(i), val: $(val)")
        end
    end

    if verbosity > 0
        daslog("Ran for $(i) iterations and $(time()-t0) seconds. Val: $(bestval)")
    end

    best = bestimum(r[1] for r in record)
    ind = findall(abs(r[1] - best) < tol*(1+abs(best) ) for r in record)

    daslog("Found $(length(ind)) solutions within $(tol*(1+abs(best) )) of $(best)")

    goodsols = record[ind]

    if length(goodsols) == 1
        vecs = goodsols 
        dists = []
        daslog("Only found one solution.")
    else
        vecs = goodsol_to_vecs(sense, goodsols)
        vecs, dists = ordered_cover(vecs, tol; fingerprint)
    
        if verbosity > 0
            rad = 1.0
            while rad >= tol
                daslog("at distance $(rad) are $(1+sum(dists .>= rad)) distinct solutions")
                rad /= 10
            end
        end
    end

    return vecs, dists

end