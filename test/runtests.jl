module SampleTypesTests

using SampleTypes
using BaseTestNext


@testset "SampleTypes Tests" begin
    include("DummySampleStream.jl")
    include("SampleBuf.jl")
    include("Interval.jl")
end

end
