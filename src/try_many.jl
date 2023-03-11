
"""
val, x = try_many(sense::Symbol, obj, gen; n_tries = Inf, t_lim = Inf, ...

Return the best of many calls of `obj` on the output of `gen`,
where best is according to `sense` which should be `:Max` or `:Min`.
Repeats for `n_tries` trials or until `t_lim` seconds pass.  One of these must be set.

# Arguments
These are required:
- `obj::Function`: The objective function
- `gen::Function`: A zero-argument function. `gen()` should generate an input to `obj`.
For example, `()->rand(4)`.
- `sense::Symbol`: `:Min` or `:Max`
At least one of the following two must be set:
- `n_tries::Integer`: An upper bound on the number of inputs to try.
- `t_lim`: Will stop after `t_lim` seconds.
The rest are optional:
- `stop_val`: will stop as soon as find a value better than this
- `file_base`: if this is non-empty, then output will be saved to `\$(file_base).txt` and `\$(file_base).jld`.
- `verbosity::Integer`: if 0, should be no output.
1, will just output a summary at the end
2, will output just the best so far each time a new one is found.
3, will output everything.
- `seed::Bool`: if negative, nothing happens.  Otherwise, seed the ith trial with the ith random seed.
- `local_rng::Bool`: if true, gen() should take a RNG as input, and it will be seeded as suggested by `seed`.
This prevents the generator for instances from intefering with any generator the algorithm might use.
- `verbose::Bool`: for backwards compatibility.  Used to set `verbosity`.
- `par_batch::Integer`: if 0, don't parallelize. If > 0, run in batches of this size.
Will force seed, unless using `local_rng`.  `local_rng` parallelizes the time of generation.
- `threads::Integer`: if 0, don't use threads. If > 0, will batch with this many threads.
Can not use this and par_batch at the same time.
- `record::Record`: fields are val, vec, status. If are set to arrays that output is appended to these.

If obj returns a structure or a tuple, then we take the first number in its output as the value of this object.
"""
function try_many(sense::Symbol, obj::Function, gen::Function;
    n_tries = Inf, t_lim = Inf,
    file_base = "",
    verbose = false,
    verbosity = 1 + 2*verbose,
    seed = false,
    local_rng = false,
    par_batch = 0,
    threads = 0,
    record = Record(),
    stop_val = (sense == :Max || sense == :max) ? Inf : -Inf)

    if n_tries == Inf && t_lim == Inf
        @warn "One of n_tries or t_lim should be set. Running just once to be safe."
        n_tries = 1
    end

    if sense == :max 
        sense = :Max
    end
    if sense == :min
        sense = :Min
    end

    val, x = try_many(obj, gen, sense;
        n_tries, t_lim,
        file_base, verbosity, 
        seed, local_rng, par_batch, threads, record, stop_val)

end

try_many(sense::typeof(min), args...; kwargs...) = try_many(:Min, args...; kwargs...)
try_many(sense::typeof(max), args...; kwargs...) = try_many(:Max, args...; kwargs...)


function try_many(func::Function, gen::Function, sense::Symbol; kwargs...)

	f2(x) = (func(x), x)
	try_many_trans(f2, gen, sense; kwargs...)

end

function first_number(out)
    for i in eachindex(out)
        if isa(out[i], Number) 
            return out[i]
        end
    end
    @warn "Return value has no numbers"
    @show out
    return NaN
end


"""
Like try_many, but func returns (val, x), where x might have been transformed.
"""
function try_many_trans(func::Function, gen::Function, sense::Symbol; n_tries = Inf, t_lim = Inf,
    file_base = "",
    verbose = false,
    verbosity = 1 + 2*verbose,
    seed = false,
    local_rng = false,
    par_batch = 0,
    threads = 0,
    record = Record(),
    stop_val = sense == :Max ? Inf : -Inf)

    @assert sense == :Max || sense == :Min
    @assert n_tries < Inf || t_lim < Inf
    @assert !local_rng || seed
    @assert threads == 0 || par_batch == 0

    if sense == :Max
        bestval = -Inf
        comp = >
    else
        bestval = Inf
        comp = <
    end

	keepbest(a,b) = comp(first_number(a), first_number(b)) ? a : b

    besta = []
    bests = []

    if !isempty(file_base)
        txt_file = "$(file_base).txt"
        jld_file = "$(file_base).jld"
    else
        txt_file, jld_file = "", ""
    end

    !isempty(file_base) && verbosity > 0 &&
        println("writing to $(txt_file) and $(jld_file)")

    info_to_file(txt_file)


    if local_rng
        rng = Random.MersenneTwister(0)
    end

    t0 = time()
    i = 0

    while (time()-t0 < t_lim && i < n_tries && comp(stop_val, bestval))

		if par_batch == 0 && threads == 0
	        if local_rng
				Random.seed!(rng, i)
	            x = gen(rng)
	        else
	            seed && Random.seed!(i)
	            x = gen()
	        end
            a = func(x)

            !isnothing(record.val) && push!(record.val, a[1])
            !isnothing(record.vec) && push!(record.vec, a[2])


        end

        if threads > 0
            inputs = Vector{Any}(undef, threads)

            Threads.@threads for j = 1:threads
                inputs[j] = (Random.seed!(i-i+j); x = func(gen()))
            end
			a = reduce(keepbest, inputs)
        end

		if par_batch > 0
			range = i:(i+par_batch-1)
			if local_rng
				outputs = pmap(j->func(gen(Random.MersenneTwister(j))), range)
				a = reduce(keepbest, outputs)
			else
				inputs = [(Random.seed!(j); x = gen()) for j in range]
				a = reduce(keepbest, pmap(func, inputs))
			end
		end

		if par_batch == 0 && threads == 0
			i += 1
		else
			i += max(par_batch, threads)
		end

        val = first_number(a)

        if comp(val,bestval)
            bestval = val
            besta = a
            push!(bests,a)
            if verbosity >= 2
		        report(i, besta, txt_file)
            end
            !isempty(file_base) && save(jld_file, "bests", bests)
        elseif verbosity > 2
            println("iteration: $(i), val: $(val)")
        end

	end

    verbosity > 0 && println("ran for $(i) iterations and $(time()-t0) seconds")

    return besta
end

"""
	report(i, val, x, txt_file)

Report iteration `i`, value `val`, vector that achieved it `x`
to text file, if it exists.  o/w just print.
"""
function report(i, val, x, txt_file)
    println("iteration $(i): value: $(val), at $(stringnow())")
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

report(i, tup::Tuple, txt_file) = report(i, first_number(tup), tup, txt_file)

function info_to_file(txt_file)
    if ~isempty(txt_file)
        fh = open(txt_file,"a")
        println(fh,"Called from: $(PROGRAM_FILE) at $(stringnow())")
        println(fh)
        close(fh)
    end
end
