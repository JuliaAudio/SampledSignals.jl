# for now we need to checkout a branch of LibSndFile to run these tests
if VERSION >= v"0.7.0-"
    using Pkg
    Pkg.add(PackageSpec(name="LibSndFile", rev="fixes07"))
else
    Pkg.checkout("LibSndFile", "fixes07")
    Pkg.add("Gumbo")
end

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
              "SinSource.jl",
              "WAVDisplay.jl"])
end
