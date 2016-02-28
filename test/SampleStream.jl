@testset "SampleStream Tests" begin
    @testset "writing sink to source" begin
        source = DummySampleSource(Float32, 48000, 2)
        sink = DummySampleSink(Float32, 48000, 2)
        data = rand(Float32, (64, 2))
        simulate_input(source, data)
        # write 20 frames at a time
        write(sink, source, 20)
        @test sink.buf == data
    end
end