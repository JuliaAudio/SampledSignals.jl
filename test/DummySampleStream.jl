@testset "DummySampleStream Tests" begin
    const DEFAULT_SR = 48000
    const DEFAULT_T = Float32

    const DummyMonoSource = DummySampleSource{1, DEFAULT_SR, DEFAULT_T}
    const DummyMonoSink = DummySampleSink{1, DEFAULT_SR, DEFAULT_T}
    const DummyStereoSource = DummySampleSource{2, DEFAULT_SR, DEFAULT_T}
    const DummyStereoSink = DummySampleSink{2, DEFAULT_SR, DEFAULT_T}
    const StereoBuf = TimeSampleBuf{2, DEFAULT_SR, DEFAULT_T}
    const MonoBuf = TimeSampleBuf{1, DEFAULT_SR, DEFAULT_T}

    @testset "simulate_input adds to buffer" begin
        source = DummyStereoSource()
        data = rand(DEFAULT_T, (64, 2))
        simulate_input(source, data)
        @test source.buf == data
    end

    @testset "simulate_input works with vector" begin
        source = DummyMonoSource()
        data = rand(DEFAULT_T, 64)
        simulate_input(source, data)
        @test vec(source.buf) == data
    end

    @testset "simulate_input throws error on wrong channel count" begin
        source = DummyStereoSource()
        data = rand(DEFAULT_T, 64, 1)
        try
            simulate_input(source, data)
            # must throw an exception
            @test false
        catch ex
            @test typeof(ex) == ErrorException
            @test ex.msg == "Simulated data channel count must match stream input count"
        end
    end

    @testset "write writes to buf" begin
        sink = DummyStereoSink()
        buf = StereoBuf(convert(Array{DEFAULT_T}, randn(32, 2)))
        write(sink, buf)
        @test sink.buf == buf.data
    end

    @testset "read reads from buf" begin
        source = DummyStereoSource()
        data = rand(DEFAULT_T, (64, 2))
        simulate_input(source, data)
        buf = read(source, 64)
        @test buf.data == data
    end

    @testset "read can read in seconds" begin
        source = DummyStereoSource()
        # fill with 1s of data
        data = rand(DEFAULT_T, (DEFAULT_SR, 2))
        simulate_input(source, data)
        buf = read(source, 0.0005s)
        @test buf.data == data[1:round(Int, 0.0005*DEFAULT_SR), :]
    end

    @testset "supports audio interface" begin
        source = DummyStereoSource()
        @test samplerate(source) == DEFAULT_SR
        @test nchannels(source) == 2
        sink = DummyStereoSink()
        @test samplerate(sink) == DEFAULT_SR
        @test nchannels(sink) == 2
        @test eltype(source) == DEFAULT_T
    end
end
