@testset "DummySampleStream Tests" begin

    const DEFAULT_SR = 48000
    const DEFAULT_T = Float32

    const DummyMonoStream = DummySampleStream{1, 1, DEFAULT_SR, DEFAULT_T}
    const DummyStereoStream = DummySampleStream{2, 2, DEFAULT_SR, DEFAULT_T}
    const StereoBuf = TimeSampleBuf{2, DEFAULT_SR, DEFAULT_T}
    const MonoBuf = TimeSampleBuf{1, DEFAULT_SR, DEFAULT_T}

    @testset "simulate_input adds to buffer" begin
        stream = DummyStereoStream()
        data = rand(DEFAULT_T, (64, 2))
        simulate_input(stream, data)
        @test stream.inbuf == data
    end

    @testset "simulate_input works with vector" begin
        stream = DummyMonoStream()
        data = rand(DEFAULT_T, 64)
        simulate_input(stream, data)
        @test vec(stream.inbuf) == data
    end

    @testset "simulate_input throws error on wrong channel count" begin
        stream = DummyStereoStream()
        data = rand(DEFAULT_T, 64, 1)
        try
            simulate_input(stream, data)
            # must throw an exception
            @test false
        catch ex
            @test typeof(ex) == ErrorException
            @test ex.msg == "Simulated data channel count must match stream input count"
        end
    end

    @testset "write writes to outbuf" begin
        stream = DummyStereoStream()
        buf = StereoBuf(convert(Array{DEFAULT_T}, randn(32, 2)))
        write(stream, buf)
        @test stream.outbuf == buf.data
    end

    @testset "read reads from inbuf" begin
        stream = DummyStereoStream()
        data = rand(DEFAULT_T, (64, 2))
        simulate_input(stream, data)
        buf = read(stream, 64)
        @test buf.data == data
    end

    @testset "read can read in seconds" begin
        stream = DummyStereoStream()
        # fill with 1s of data
        data = rand(DEFAULT_T, (DEFAULT_SR, 2))
        simulate_input(stream, data)
        buf = read(stream, 0.5s)
        @test buf.data == data[1:round(Int, DEFAULT_SR/2), :]
    end

    @testset "supports samplerate" begin
        stream = DummyStereoStream()
        @test samplerate(stream) == DEFAULT_SR
    end
end
