stringnow() = Dates.format(now(),"u d Y, HH:MM:SS")

function docsdir()
    p = pathof(DASopt)
    ind = findall("/",p)
    return "$(p[1:ind[end-1][1]])docs/build/index.html"
end