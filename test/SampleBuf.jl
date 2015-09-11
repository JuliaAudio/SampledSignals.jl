@testset "SampleBuf Tests" begin
    TEST_SR = 48000
    TEST_T = Float32
    const StereoBuf = TimeSampleBuf{2, TEST_SR, TEST_T}

    @testset "SampleBuf supports size()" begin
        buf = StereoBuf(zeros(TEST_T, 64, 2))
        @test size(buf) == (64, 2)
    end

    @testset "TimeSampleBuf can be indexed with 1D indices" begin
        buf = StereoBuf(zeros(TEST_T, 64, 2))
        buf[15, 2] = 1.5
        @test buf[20] == 0.0
        @test buf[64+15] == 1.5
    end

    @testset "TimeSampleBuf can be indexed with 2D indices" begin
        buf = StereoBuf(zeros(TEST_T, 64, 2))
        buf[15, 2] = 1.5
        @test buf[15, 1] == 0.0
        @test buf[15, 2] == 1.5
    end

    @testset "SampleBufs can get type params from contained array" begin
        timebuf = TimeSampleBuf(Array(TEST_T, 32, 2), TEST_SR)
        @test typeof(timebuf) == TimeSampleBuf{2, TEST_SR, TEST_T}
        freqbuf = FrequencySampleBuf(Array(TEST_T, 32, 2), TEST_SR)
        @test typeof(freqbuf) == FrequencySampleBuf{2, TEST_SR, TEST_T}
    end
end
