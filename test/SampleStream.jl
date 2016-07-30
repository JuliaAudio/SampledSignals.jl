# these tests use generalized SampleSink and SampleSource functionality. They
# use Dummy sinks and sources, but all these features should be implemented
# on the abstract Source/Sinks
@testset "SampleStream Tests" begin
    @testset "writing sink to source" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        # write 20 frames at a time
        n = write(sink, source, blocksize=20)
        @test n == 64
        @test sink.buf == data
    end

    @testset "single-to-multi channel stream conversion" begin
        data = rand(Float32, 64, 1)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        write(sink, source, blocksize=20)
        @test sink.buf == [data data]
    end

    @testset "multi-to-single channel stream conversion" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 1)
        write(sink, source, blocksize=20)
        @test sink.buf == data[:, 1:1] + data[:, 2:2]
    end

    @testset "format conversion" begin
        data = rand(Float64, 64, 2)
        fdata = convert(Array{Float32}, data)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        write(sink, source, blocksize=20)
        @test sink.buf == fdata
    end

    """Linearly interpolate the given array"""
    function linterp(v::AbstractArray, sr::Real, t::Real)
        idx = sr*t+1
        left = round(Int, idx, RoundDown)
        right = left+1
        offset = idx - left

        right > size(v, 1) && error("Tried to interpolate past the end of the vector")

        v[left, :] * (1-offset) + v[right, :] * offset
    end

    @testset "samplerate conversion" begin
        sr1 = 48000
        data1 = rand(Float32, 64, 2)
        sr2 = 44100
        data2 = Array(Float32, (63 * sr2)÷sr1+1, 2)
        for i in 1:size(data2, 1)
            t = (i-1) / sr2
            data2[i, :] = linterp(data1, sr1, t)
        end

        source = DummySampleSource(sr1, data1)
        sink = DummySampleSink(Float32, sr2, 2)
        write(sink, source, blocksize=20)
        @test isapprox(sink.buf, data2)
    end

    @testset "combined conversion" begin
        sr1 = 48000
        data1 = rand(Float32, 64, 1) - 0.5
        sr2 = 44100
        data2 = Array(Fixed{Int16, 15}, ((size(data1, 1)-1) * sr2)÷sr1+1, 2)
        for i in 1:size(data2, 1)
            t = (i-1) / sr2
            v = linterp(data1, sr1, t)
            data2[i, :] = [v v]
        end

        source = DummySampleSource(sr1, data1)
        sink = DummySampleSink(Fixed{Int16, 15}, sr2, 2)
        write(sink, source, blocksize=20)
        # we can get slightly different results depending on whether we resample
        # before or after converting data types
        @test isapprox(sink.buf, data2)
    end

    @testset "stream reading supports frame count larger than blocksize" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        n = write(sink, source, 20, blocksize=8)
        @test n == 20
        @test sink.buf == data[1:20, :]
    end

    @testset "stream reading supports frame count smaller than blocksize" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        n = write(sink, source, 10, blocksize=20)
        @test n == 10
        @test sink.buf == data[1:10, :]
    end

    @testset "stream reading supports duration in seconds" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000Hz, data)
        sink = DummySampleSink(Float32, 48000Hz, 2)
        duration = 20 / 48000
        # we should get back the exact duration given even if it's not exactly
        # on a sample boundary
        duration = (duration + eps(duration)) * s
        t = write(sink, source, duration, blocksize=8)
        @test t == duration
        @test sink.buf == data[1:20, :]
    end

    @testset "stream reading supports duration in seconds when stream ends" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000Hz, data)
        sink = DummySampleSink(Float32, 48000Hz, 2)
        duration = 1.0s
        t = write(sink, source, duration, blocksize=8)
        @test t == (64/48000) * s
        @test sink.buf == data
    end

    @testset "SampleBufSource can wrap SampleBuf" begin
        buf = SampleBuf(rand(16, 2), 48000Hz)
        source = SampleBufSource(buf)
        @test read(source, 8) == buf[1:8, :]
    end

    @testset "SampleBufs can be written to sinks with conversion" begin
        buf = SampleBuf(rand(16, 2), 48000Hz)
        sink = DummySampleSink(Float64, 48000Hz, 1)
        write(sink, buf)
        @test sink.buf[:] == buf[:, 1] + buf[:, 2]
    end

    @testset "SampleBufSink can wrap SampleBuf" begin
        sourcebuf = SampleBuf(rand(Float32, 64, 2), 48000Hz)
        sinkbuf = SampleBuf(Float32, 48000Hz, 32, 2)
        sink = SampleBufSink(sinkbuf)
        @test write(sink, sourcebuf) == 32
        @test sinkbuf == sourcebuf[1:32, :]
    end

    @testset "SampleBufs can be read from sources with conversion" begin
        buf = SampleBuf(Float64, 48000Hz, 32)
        data = rand(Float64, 64, 2)
        source = DummySampleSource(48000Hz, data)
        read!(source, buf)
        @test buf == data[1:32, 1] + data[1:32, 2]
    end

    @testset "blocksize fallback returns 0" begin
        @test blocksize(DummySampleSource(48000Hz, zeros(5, 2))) == 0
        @test blocksize(DummySampleSink(Float32, 48000Hz, 2)) == 0
    end

    @testset "Writing source to sink goes blockwise" begin
        source = BlockedSampleSource(32)
        sink = DummySampleSink(eltype(source), samplerate(source), nchannels(source))
        write(sink, source)
        @test size(sink.buf, 1) == 32
        for ch in 1:nchannels(source), i in 1:16
            @test sink.buf[i, ch] == i * ch
        end
        for ch in 1:nchannels(source), i in 17:32
            @test sink.buf[i, ch] == (i-16) * ch
        end
    end
end
