@testset "SampleStream Tests" begin
    @testset "writing sink to source" begin
        data = rand(Float32, (64, 2))
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        # write 20 frames at a time
        write(sink, source, 20)
        @test sink.buf == data
    end
    
    # @testset "single-to-multi channel conversion" begin
    #     data = rand(Float32, (64, 2))
    #     source = DummySampleSource(48000, data)
    #     sink = DummySampleSink(Float32, 48000, 2)
    #     
    # end
end