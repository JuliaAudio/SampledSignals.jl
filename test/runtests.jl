using SampledSignals
using Compat.Test
using DSP
using FixedPointNumbers
using Gumbo
using FileIO: File, Stream, @format_str
import LibSndFile

include("support/util.jl")

@testset "SampledSignals Tests" begin
    include.(["DummySampleStream.jl",
              "SampleBuf.jl",
              "SampleStream.jl",
              "WAVDisplay.jl"])
end

