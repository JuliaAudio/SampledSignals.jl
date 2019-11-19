using SampledSignals
using Compat.Test
using DSP
using FixedPointNumbers
using FileIO: File, Stream, @format_str
# for now we're disabling the wav display tests so we don't need to include
# LibSndFile in our test dependencies. We can re-enable it once all the
# BinaryBuilder stuff is worked out
# import LibSndFile

include("support/util.jl")

@testset "SampledSignals Tests" begin
    include.(["DummySampleStream.jl",
              "SampleBuf.jl",
              "SampleStream.jl",
              "SinSource.jl",
              # "WAVDisplay.jl"
              ])
end
