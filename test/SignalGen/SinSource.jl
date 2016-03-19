@testset "SinSource Tests" begin
    @testset "SinSource generates sin" begin
        source = SinSource(Float32, 44100Hz, [220Hz, 440Hz])
        t = (0:31) / 44100
        expected = Float32[sin(2pi*220*t) sin(2pi*440*t)]
        @test read(source, 32) ≈ expected
    end

    @testset "SinSource generates works with one frequency" begin
        source = SinSource(Float32, 44100Hz, 220Hz)
        t = (0:31) / 44100
        expected = Float32[sin(2pi*220*t);]
        @test read(source, 32) ≈ expected
    end
end
