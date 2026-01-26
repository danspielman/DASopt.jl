stringnow() = Dates.format(now(),"u d Y, HH:MM:SS")

safeintdiv(a,b) = a == Inf ? Inf : a ÷ b

function docsdir()
    p = pathof(DASopt)
    ind = findall("/",p)
    return "$(p[1:ind[end-1][1]])docs/build/index.html"
end

sensemap(sense::typeof(min)) = :Min 
sensemap(sense::typeof(max)) = :Max 
function sensemap(sense::Symbol)
    if sense == :min
        return :Min
    elseif sense == :max 
        return :Max 
    elseif sense == :Max
        return :Max
    elseif sense == :Min
        return :Min
    else
        error("Invalid sense. Try using one of :Max or :Min.")
    end
end

function info_to_file(txt_file)
    if ~isempty(txt_file)
        fh = open(txt_file,"a")
        println(fh,"Called from: $(PROGRAM_FILE) at $(stringnow())")
        println(fh)
        close(fh)
    end
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
