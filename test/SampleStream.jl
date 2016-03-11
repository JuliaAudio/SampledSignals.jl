# these tests use generalized SampleSink and SampleSource functionality. They
# use Dummy sinks and sources, but all these features should be implemented
# on the abstract Source/Sinks
@testset "SampleStream Tests" begin
    @testset "writing sink to source" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        # write 20 frames at a time
        write(sink, source, 20)
        @test sink.buf == data
    end

    @testset "single-to-multi channel stream conversion" begin
        data = rand(Float32, 64, 1)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        write(sink, source, 20)
        @test sink.buf == [data data]
    end

    @testset "multi-to-single channel stream conversion" begin
        data = rand(Float32, 64, 2)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 1)
        write(sink, source, 20)
        @test sink.buf == data[:, 1:1] + data[:, 2:2]
    end

    @testset "format conversion" begin
        data = rand(Float64, 64, 2)
        fdata = convert(Array{Float32}, data)
        source = DummySampleSource(48000, data)
        sink = DummySampleSink(Float32, 48000, 2)
        write(sink, source, 20)
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
        write(sink, source, 20)
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
        write(sink, source, 20)
        # we can get slightly different results depending on whether we resample
        # before or after converting data types
        @test isapprox(sink.buf, data2)
    end
end