@testset "SinSource Tests" begin
    @testset "SinSource generates sin" begin
        source = SinSource(Float32, 44100, [220, 440])
        t = (0:31) / 44100
        expected = Float32[sin.(2pi*220*t) sin.(2pi*440*t)]
        @test read(source, 32) ≈ expected
    end

    @testset "SinSource generates works with one frequency" begin
        source = SinSource(Float32, 44100, 220)
        t = (0:31) / 44100
        expected = Float32[sin.(2pi*220*t);]
        @test read(source, 32) ≈ expected
    end

    @testset "SinSource can write to a sink without units" begin
        source = SinSource(Float32, 44100, 220)
        sink = DummySampleSink(Float32, 44100, 1)
        t = (0:31) / 44100
        expected = Float32[sin.(2pi*220*t);]
        write(sink, source, 32)
        @test sink.buf ≈ expected
    end
end
