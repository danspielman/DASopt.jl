stringnow() = Dates.format(now(),"u d Y, HH:MM:SS")

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

