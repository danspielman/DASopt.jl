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

"""
    bestval, comp, bestimum, argbest = bestfuns(sense)
"""
function bestfuns(sense)
    sense = sensemap(sense)
    if sense == :Max
        bestval = -Inf
        comp = >
        bestimum = maximum
        argbest = argmax
    else
        bestval = Inf
        comp = <
        bestimum = minimum
        argbest = argmin
    end
    return bestval, comp, bestimum, argbest
end

