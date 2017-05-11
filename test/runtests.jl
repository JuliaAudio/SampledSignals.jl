using SampledSignals
using Base.Test
using TestSetExtensions
import SIUnits
using DSP
using FixedPointNumbers
using Gumbo
using WAV

include("support/util.jl")

try
    @testset DottedTestSet "SampledSignals Tests" begin
        @includetests ARGS
    end
catch err
    exit(-1)
end
