@testset "Unit conversion Tests" begin
    @testset "converting to seconds" begin
        @test inseconds(1s) == inseconds(1000ms)
        @test inseconds(1.0) == 1.0
        @test inseconds(1.0s) == 1.0
        @test inseconds(10ms) == 1//100
        @test inseconds(441frames,44100Hz) == 0.01
        @test inseconds(1.0s,44100Hz) == 1.0
        @test inseconds(10ms,44100Hz) == 1//100
        @test inseconds(1.0,44100Hz) == 1.0
        @test inseconds(1.0,44100Hz) == inseconds(1.0)
        @test_throws ErrorException inseconds(441frames)
    end

    @testset "converting to frames" begin
        @test inframes(1s,44100Hz) == inframes(1000ms,44100Hz)
        @test inframes(Int,0.5s,44100Hz) == 22050
        @test inframes(Int,10frames,44100Hz) == 10
        @test inframes(10.5frames,44100Hz) == 10.5
        @test inframes(10frames) == 10
        @test inframes(10) == 10
        @test inframes(1s, 44100) == inframes(1000ms,44100Hz)
        @test inframes(10Hz, 0.1) == 1
        @test inframes(Int, 1) == inframes(1)
        @test_throws ErrorException inframes(1s)
        @test_throws ErrorException inframes(Int, 1s)
    end

    @testset "converting to Hz" begin
        @test inHz(100Hz) == inHz(0.1kHz)
        @test inHz(100Hz) == 100
        @test inHz(1kHz) == 1000
        @test inHz(100) == 100
        @test inHz(441frames, 1000) == 0.441
        @test inHz(1.0, 441000) == inHz(1.0)
        @test_throws ErrorException inHz(441frames)
    end
end
