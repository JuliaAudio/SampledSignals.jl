# these tests use generalized SampleSink and SampleSource functionality. They
# use Dummy sinks and sources, but all these features should be implemented
# on the abstract Source/Sinks
@testset "SampleStream Tests" begin
    @testset "writing sink to source" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        # write 20 frames at a time
        write(sink, source, 20)
        @test sink.buf == data
    end

    @testset "single-to-multi channel stream conversion" begin
        data = rand(Float32, 64, 1)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        write(sink, source, 20)
        @test sink.buf == [data data]
    end
    
    @testset "multi-to-single channel stream conversion" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 1)
        write(sink, source, 20)
        @test sink.buf == data[:, 1:1] + data[:, 2:2]
    end
    
    @testset "format conversion" begin
        data = rand(Float64, 64, 2)
        fdata = convert(Array{Float32}, data)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        write(sink, source, 20)
        @test sink.buf == fdata
    end
end