using SampledSignals
using Compat
import SIUnits
using DSP

import Compat.view

if VERSION >= v"0.5.0-dev+7720"
    using Base.Test
else
    using BaseTestNext
end

using TestSetExtensions
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
