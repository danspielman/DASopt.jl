
"""
    x, val = try_many(obj::Function, gen::Function, sense::Symbol; n = Inf, t_lim = Inf, ...

Return the best of many calls of `obj` on the output of `gen`,
where best is according to `sense` which should be `:Max` or `:Min`.
Repeats for `n` trials or until `t_lim` seconds pass.  One of these must be set.

# Arguments
- `obj::Function`: The objective function
- `gen::Function`: A zero-argument function. `gen()` should generate an input to `obj`.
   For example, `()->rand(4)`.
- `sense::Symbol`: `:Min` or `:Max`
- `n::Integer`: An upper bound on the number of inputs to try.
- `t_lim`: Will stop after `t_lim` seconds.
- `fn_base`: if this is non-empty, then output will be saved to `\$(fn_base).txt` and `\$(fn_base).jld`.
- `verbosity::Integer`: if 0, should be no output.
    1, will output just the best so far each time a new one is found.
    2, will output everything.
- `seed::Bool`: if negative, nothing happens.  Otherwise, seed the ith trial with the ith random seed.
- `local_rng::Bool`: if true, gen() should take a RNG as input, and it will be seeded as suggested by `seed`.
  This prevents the gen erator for instances from intefering with any generator the algorithm might use.
- `verbose::Bool`: for backwards compatibility.  Used to set `verbosity`.
"""
function try_many(func::Function, gen::Function, sense::Symbol; kwargs...)

	f2(x) = (x, func(x))
	try_many_trans(f2, gen, sense; kwargs...)

end

"""
Like try_many, but func returns (x, val), where x has been transformed.
"""
function try_many_trans(func::Function, gen::Function, sense::Symbol; n = Inf, t_lim = Inf,
    fn_base = "",
    verbose = false,
    verbosity = 1 + verbose,
    seed = false,
    local_rng = false)

    @assert sense == :Max || sense == :Min
    @assert n < Inf || t_lim < Inf
    @assert !local_rng || seed

    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

    bestx = []
    bests = []

    if !isempty(fn_base)
        txt_file = "$(fn_base).txt"
        jld_file = "$(fn_base).jld"
    else
        txt_file, jld_file = "", ""
    end

    !isempty(fn_base) && verbosity > 0 &&
        println("writing to $(txt_file) and $(jld_file)")

    info_to_file(txt_file)


    if local_rng
        rng = Random.MersenneTwister(0)
    end

    t0 = time()
    i = 0
    while (time()-t0 < t_lim && i < n)
        i += 1

        if local_rng
            x = gen(rng)
        else
            seed && Random.seed!(i)
            x = gen()
        end

        x, val = func(x)
        if comp(val,bestval)
            bestval = val
            bestx = x
            push!(bests,x)
            if verbosity > 0
		        report(i, val, bestx, txt_file)
            end
            !isempty(fn_base) && save(jld_file, "bests", bests)
        elseif verbosity > 1
            println("iteration: $(i), val: $(val)")
        end
    end

    verbosity > 0 && println("ran for $(i) iterations and $(time()-t0) seconds")

    return bestx, bestval
end

"""
	report(i, val, x, txt_file)

Report iteration `i`, value `val`, vector that achieved it `x`
to text file, if it exists.  o/w just print.
"""
function report(i, val, x, txt_file)
    println("iteration $(i): value: $(val), at $(now())")
    println(x)
    println()

    if ~isempty(txt_file)
        fh = open(txt_file,"a")
        println(fh,"iteration $(i): value: $(val)")
        println(fh,x)
        println(fh)
        close(fh)
    end
end


function info_to_file(txt_file)
    if ~isempty(txt_file)
        fh = open(txt_file,"a")
        println(fh,"Called from: $(PROGRAM_FILE) at $(now())")
        println(fh)
        close(fh)
    end
end
