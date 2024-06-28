using NaNStatistics
using Test, StatsBase, Statistics, LinearAlgebra, Distributions

@testset "ArrayStats" begin include("testArrayStats.jl") end
@testset "Covariance and Correlation" begin include("testCovCor.jl") end
@testset "Sorting" begin include("testSorting.jl") end

@testset "Histograms" begin include("testHistograms.jl") end
@testset "Binning" begin include("testBinning.jl") end
