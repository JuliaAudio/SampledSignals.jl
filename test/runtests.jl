using SampledSignals
using Compat.Test
using TestSetExtensions
using DSP
using FixedPointNumbers
using Gumbo
using WAV

include("support/util.jl")

@testset ExtendedTestSet "SampledSignals Tests" begin
    include.(["DummySampleStream.jl", "Interval.jl", "SampleBuf.jl", "SampleStream.jl", "SinSource.jl", "WAVDisplay.jl"])
    # @includetests ARGS
end
