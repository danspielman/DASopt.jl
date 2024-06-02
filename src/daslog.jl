# daslog

log_file = ""
to_stdout = true
worker_stdout = false

"""
    daslog(args...)

Use in place of println. Will got to stdout by default.
But, can also go to log file.
"""
function daslog(args...)
    daslo(args..., "\n")
end

"""
    daslo(args...)  
    
The `print`, as opposed to `println`, analog of daslog.
"""
function daslo(args...)
    isworker = false

    id = []
    try id = myid()
        if id > 1
            isworker = true
            DASopt.worker_stdout =  @fetchfrom 1 DASopt.worker_stdout
            DASopt.to_stdout =  @fetchfrom 1 DASopt.to_stdout
            DASopt.log_file =  @fetchfrom 1 DASopt.log_file    
        end
    catch e 
    end

    !isworker && DASopt.to_stdout && print(args...)
    isworker && DASopt.worker_stdout && print(args...)

    if !isempty(DASopt.log_file)   
        fn = DASopt.log_file
        if isworker
             fn *= "_p$(id)"
        end
        
        fh = open(fn,"a")
        print(fh,args...)
        close(fh)
    end
end


function daslog_stat()
    if isempty(DASopt.log_file)
        println("no log file")
    else
        println("logging to $(DASopt.log_file)")
    end

    println("log to stdout: $(DASopt.to_stdout)")
    println("send worker output to stdout: $(DASopt.worker_stdout)")    
end


"""
    set_logfile(logfn::String)    

Set the name of the log file.
If logfn is empty, use default_logfn().
"""
function start_logfile(logfn::String)
    DASopt.log_file = logfn
    fh = open(log_file,"a")
    println(fh, "Log file started on $(stringnow())")
    close(fh)
    println("Logging to: $logfn")
end

start_logfile() = start_logfile(default_logname())

"""
    default_logname(;progname=true, hostname=true, args=true, date=true)
"""
function default_logname(;progname=true, hostname=true, args=true, date=true)

    if isdefined(Main, :IJulia)
        progname = false
        args = false
    end

    if progname
        s = split(PROGRAM_FILE, "/")[end]
    else
        s = "" 
    end

    if hostname 
        hn = split(gethostname(), ".")[1]
        hn = split(hn, "-")[1]
        s *= (!isempty(s) ? "_" : "") * hn
    end

    if args
        for a in ARGS
            s *= (!isempty(s) ? "_" : "") * a
        end
    end

    if isempty(s)
        s = "Julia"
    end

    if date
        s *= "_"
        s *= Dates.format(now(),"Y_u_d_HH:MM")
    end

    s *= ".log"

end

function merge_worker_logs()
    if isempty(DASopt.log_file)
        println("warning: there is no log file to merge")
        return 
    end

    try id = myid()
        if id > 1
            @warn "Shouldn't try to merge logs from a worker process"
            return           
        end
    catch e 
    end

    fn = DASopt.log_file * "_p"

    files = readdir()

    for file in files
        if startswith(file, fn)
            open(file) do fw
                rl = readlines(fw)

                pnum = split(file,'_')[end]
                open(DASopt.log_file,"a") do f
                    println(f,"-------------------")
                    println(f, "From worker: $pnum")
                    println(f)
                    for l in rl
                        println(f, l)
                    end
                    println(f)
                end
            end
            rm(file)
        end
    end
end