using SampleTypes

if VERSION >= v"0.5.0-"
    using Base.Test
else
    using BaseTestNext
end

# try
    @testset "SampleTypes Tests" begin
        include("DummySampleStream.jl")
        include("SampleBuf.jl")
        include("Interval.jl")
    end
# catch err
#     exit(-1)
# end
