# these tests use generalized SampleSink and SampleSource functionality. They
# use Dummy sinks and sources, but all these features should be implemented
# on the abstract Source/Sinks
@testset "SampleStream Tests" begin
    DummySource(buf) = DummySampleSource(48000, buf)
    DummyMonoSink() = DummySampleSink(Float64, 48000, 1)
    DummyStereoSink() = DummySampleSink(Float64, 48000, 2)

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
        data = rand(Float32, 16, 2) - 0.5
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(PCM16Sample, 48000, 2)
        # the write function tests that the format matches
        write(sink, source)
        @test sink.buf == map(PCM16Sample, data)
    end

    @testset "downsampling conversion" begin
        sr1 = 48000
        sr2 = 9000

        data1 = rand(Float32, 64, 2)
        ratio = sr2//sr1
        data2 = mapslices(c->filt(FIRFilter(resample_filter(ratio), ratio), c),
                          data1,
                          1)

        source = DummySampleSource(sr1, data1)
        sink = DummySampleSink(Float32, sr2, 2)
        write(sink, source, blocksize=20)
        @test size(sink.buf) == size(data2)
        @test sink.buf == map(Float32, data2)
    end

    @testset "upsampling conversion" begin
        sr1 = 9000
        sr2 = 48000

        data1 = rand(Float32, 64, 2)
        ratio = sr2//sr1
        data2 = mapslices(c->filt(FIRFilter(resample_filter(ratio), ratio), c),
                          data1,
                          1)

        source = DummySampleSource(sr1, data1)
        sink = DummySampleSink(Float32, sr2, 2)
        write(sink, source, blocksize=20)
        @test size(sink.buf) == size(data2)
        @test sink.buf == map(Float32, data2)
    end

    @testset "combined conversion" begin
        sr1 = 48000
        data1 = rand(Float32, 64, 1) - 0.5
        sr2 = 44100
        ratio = sr2//sr1
        data2 = map(PCM16Sample, hcat(
            filt(FIRFilter(resample_filter(ratio), ratio), vec(data1)),
            filt(FIRFilter(resample_filter(ratio), ratio), vec(data1))
        ))

        source = DummySampleSource(sr1, data1)
        sink = DummySampleSink(PCM16Sample, sr2, 2)
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
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
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
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        duration = 1.0s
        t = write(sink, source, duration, blocksize=8)
        @test t == (64/48000)
        @test sink.buf == data
    end

    @testset "SampleBufSource can wrap SampleBuf" begin
        buf = SampleBuf(rand(16, 2), 48000)
        source = SampleBufSource(buf)
        @test read(source, 8) == buf[1:8, :]
    end

    @testset "SampleBufs can be written to sinks" begin
        buf = SampleBuf(rand(16, 2), 48000)
        sink = DummySampleSink(Float64, 48000, 2)
        write(sink, buf)
        @test sink.buf == buf
    end

    @testset "Arrays can be written to sinks" begin
        arr = rand(16, 2)
        sink = DummySampleSink(Float64, 48000, 2)
        write(sink, arr)
        @test sink.buf == arr
    end

    @testset "Partial SampleBufs can be written to sinks specifying frames" begin
        sink = DummyStereoSink()
        buf = SampleBuf(rand(10, 2), samplerate(sink))
        write(sink, buf, 5)
        @test sink.buf == buf.data[1:5, :]
    end

    @testset "Partial Arrays can be written to sinks specifying frames" begin
        sink = DummyStereoSink()
        buf = rand(10, 2)
        write(sink, buf, 5)
        @test sink.buf == buf[1:5, :]
    end

    @testset "Partial SampleBufs can be written to sinks specifying duration" begin
        sink = DummyStereoSink()
        buf = SampleBuf(rand(10, 2), samplerate(sink))
        t = 5/samplerate(sink) * s
        write(sink, buf, t)
        @test sink.buf == buf.data[1:5, :]
    end

    @testset "Partial Arrays can be written to sinks specifying duration" begin
        sink = DummyStereoSink()
        buf = rand(10, 2)
        t = 5/samplerate(sink) * s
        write(sink, buf, t)
        @test sink.buf == buf[1:5, :]
    end

    @testset "can read without specifying frames" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = read(source)
        @test buf isa SampleBuf
        @test buf.data == data
    end

    @testset "can read long source without specifying frames" begin
        data = rand(10000, 2)
        source = DummySource(data)
        buf = read(source)
        @test buf isa SampleBuf
        @test buf.data == data
    end

    @testset "read can read in frames" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = read(source, 5)
        @test buf.data == data[1:5, :]
    end

    @testset "read can read in seconds" begin
        data = rand(20, 2)
        source = DummySource(data)
        t = 5/samplerate(source) * s
        buf = read(source, t)
        @test buf.data == data[1:5, :]
    end

    @testset "can read! into array specifying frames" begin
        data = rand(8, 2)
        buf = zeros(8, 2)
        source = DummySource(data)
        @test read!(source, buf, 5) == 5
        @test buf[1:5, :] == data[1:5, :]
        @test buf[6:8, :] == zeros(3, 2)
    end

    @testset "can read! into SampleBuf specifying frames" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = SampleBuf(zeros(8, 2), samplerate(source))
        @test read!(source, buf, 5) == 5
        @test buf.data[1:5, :] == data[1:5, :]
        @test buf.data[6:8, :] == zeros(3, 2)
    end

    @testset "can read! into array specifying time" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = zeros(8, 2)
        t = 5/samplerate(source) * s
        @test read!(source, buf, t) == t
        @test buf[1:5, :] == data[1:5, :]
        @test buf[6:8, :] == zeros(3, 2)
    end

    @testset "can read! into SampleBuf specifying time" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = SampleBuf(zeros(8, 2), samplerate(source))
        t = 5/samplerate(source) * s
        @test read!(source, buf, t) == t
        @test buf.data[1:5, :] == data[1:5, :]
        @test buf.data[6:8, :] == zeros(3, 2)
    end

    @testset "can read! into array without specifying frames" begin
        data = rand(8, 2)
        buf = rand(5, 2)
        source = DummySource(data)
        @test read!(source, buf) == 5
        @test buf == data[1:5, :]
    end

    @testset "can read! into SampleBuf without specifying frames" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = SampleBuf(rand(5, 2), samplerate(source))
        @test read!(source, buf) == 5
        @test buf.data == data[1:5, :]
    end

    @testset "can read! into too-long array without specifying frames" begin
        data = rand(8, 2)
        buf = zeros(10, 2)
        source = DummySource(data)
        @test read!(source, buf) == 8
        @test buf[1:8, :] == data
        @test buf[9:10, :] == zeros(2, 2)
    end

    @testset "can read! into too-long SampleBuf without specifying frames" begin
        data = rand(8, 2)
        source = DummySource(data)
        buf = SampleBuf(zeros(10, 2), samplerate(source))
        @test read!(source, buf) == 8
        @test buf[1:8, :] == data
        @test buf[9:10, :] == zeros(2, 2)
    end

    @testset "SampleBufs can be written to sinks with downmixing" begin
        buf = SampleBuf(rand(16, 2), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf)
        @test sink.buf[:] == buf[:, 1] + buf[:, 2]
    end

    @testset "Arrays can be written to sinks with downmixing" begin
        arr = rand(16, 2)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, arr)
        @test sink.buf[:] == arr[:, 1] + arr[:, 2]
    end

    @testset "SampleBufs can be written to sinks with duration in frames" begin
        buf = SampleBuf(rand(16), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf, 10)
        @test sink.buf[:] == buf[1:10]
    end

    @testset "SampleBufs can be written to sinks with duration in unitful frames" begin
        buf = SampleBuf(rand(16), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf, 10frames)
        @test sink.buf[:] == buf[1:10]
    end

    @testset "SampleBufs can be written to sinks with duration in seconds" begin
        buf = SampleBuf(rand(100), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf, 0.001s)
        @test sink.buf[:] == buf[1:48]
    end

    @testset "SampleBufs can be written to sinks with duration in frames and format conversion" begin
        buf = SampleBuf(map(PCM16Sample, rand(16)-0.5), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf, 10)
        @test sink.buf[:] == map(Float64, buf[1:10])
    end

    @testset "SampleBufs can be written to sinks with duration in seconds and format conversion" begin
        buf = SampleBuf(map(PCM16Sample, rand(100)-0.5), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf, 0.001s)
        @test sink.buf[:] == map(Float64, buf[1:48])
    end

    @testset "SampleBufs can be written to sinks with format conversion" begin
        buf = SampleBuf(map(PCM16Sample, rand(16)-0.5), 48000)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, buf)
        @test sink.buf[:] == map(Float64, buf)
    end

    @testset "Arrays can be written to sinks with format conversion" begin
        arr = map(PCM16Sample, rand(16, 1)-0.5)
        sink = DummySampleSink(Float64, 48000, 1)
        write(sink, arr)
        @test sink.buf == map(Float64, arr)
    end

    @testset "SampleBufSink can wrap SampleBuf" begin
        sourcebuf = SampleBuf(rand(Float32, 64, 2), 48000)
        sinkbuf = SampleBuf(Float32, 48000, 32, 2)
        sink = SampleBufSink(sinkbuf)
        @test write(sink, sourcebuf) == 32
        @test sinkbuf == sourcebuf[1:32, :]
    end

    @testset "Arrays can be read from sources" begin
        arr = Array{Float64}(16, 2)
        data = rand(Float64, 16, 2)
        source = DummySampleSource(48000, data)
        read!(source, arr)
        @test arr == data
    end

    @testset "SampleBufs can be read from sources with conversion" begin
        buf = SampleBuf(Float64, 48000, 32)
        data = rand(Float64, 64, 2)
        source = DummySampleSource(48000, data)
        read!(source, buf)
        @test buf == data[1:32, 1] + data[1:32, 2]
    end

    @testset "SampleBufs can be read from sources with duration in frames" begin
        buf = SampleBuf(Float64, 48000, 32)
        data = rand(Float64, 64, 2)
        source = DummySampleSource(48000, data)
        read!(source, buf)
        @test buf == data[1:32, 1] + data[1:32, 2]
    end

    @testset "blocksize fallback returns 0" begin
        @test blocksize(DummySampleSource(48000, zeros(5, 2))) == 0
        @test blocksize(DummySampleSink(Float32, 48000, 2)) == 0
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
