@testset "SampleBuf Tests" begin
    DEFAULT_SR = 48000
    DEFAULT_T = Float32
    const StereoBuf = TimeSampleBuf{2, DEFAULT_SR, DEFAULT_T}

    @testset "SampleBuf supports size()" begin
        buf = StereoBuf(zeros(DEFAULT_T, 64, 2))
        @test size(buf) == (64, 2)
    end

    @testset "TimeSampleBuf can be indexed with 1D indices"
        buf = StereoBuf(zeros(DEFAULT_T, 64, 2))
        buf[15, 2] = 1.5
        @test buf[20] == 0.0
        @test buf[20] == 1.5
    end

    # @testset "TimeSampleBuf can be indexed with 2D indices"
    #     buf = StereoBuf(zeros(DEFAULT_T, 64, 2))
    #     buf[15, 2] = 1.5
    #     @test buf[15, 1] == 0.0
    #     @test buf[15, 2] == 1.5
    # end
end
