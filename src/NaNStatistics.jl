module NaNStatistics

    # AVX vectorziation tools
    using IfElse: ifelse
    using LoopVectorization

    using Static
    const IntOrStaticInt = Union{Integer, StaticInt}
    _dim(::Type{StaticInt{N}}) where {N} = N::Int

    include("ArrayStats/ArrayStats.jl")
    include("ArrayStats/nanmean.jl")
    include("ArrayStats/nansum.jl")
    include("ArrayStats/nancumsum.jl")
    include("ArrayStats/nanvar.jl")
    include("ArrayStats/nanstd.jl")
    include("ArrayStats/nancov.jl")
    include("Sorting/quicksort.jl")
    include("Sorting/nanmedian.jl")
    include("Sorting/nanpctile.jl")
    include("Histograms.jl")
    include("Binning.jl")

end
