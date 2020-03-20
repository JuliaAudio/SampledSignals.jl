@inline loadwav(fname::String, args...) = LibSndFile.load(File(format"WAV", fname), args...)
@inline loadwav(io::IO, args...) = LibSndFile.load(Stream(format"WAV", io), args...)

@testset "WAVDisplay Tests" begin
    @testset "wavwrite Generates valid WAV file with raw Int16" begin
        buf = SampleBuf(rand(Int16, 4, 2), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        seekstart(io)
        readbuf = loadwav(io)
        @test reinterpret.(readbuf) == buf
        @test framerate(readbuf) == 48000
        @test eltype(readbuf) == Fixed{Int16, 15}
    end

    @testset "wavwrite Generates valid WAV file with raw 16-bit Fixed-point" begin
        buf = SampleBuf(reinterpret.(Fixed{Int16, 15}, rand(Int16, 4, 2)), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        seek(io, 0)
        readbuf = loadwav(io)
        @test readbuf == buf
        @test framerate(readbuf) == 48000
        @test eltype(readbuf) == Fixed{Int16, 15}
    end

    @testset "wavwrite converts float values to 16-bit int wav" begin
        buf = SampleBuf(rand(4, 2) .- 0.5, 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        seekstart(io)
        readbuf = loadwav(io)
        @test readbuf == PCM16Sample.(buf)
        @test framerate(readbuf) == 48000
        @test eltype(readbuf) == Fixed{Int16, 15}
    end

    @testset "wavwrite converts Int32 values to 16-bit int wav" begin
        data = rand(4, 2).-0.5
        buf = SampleBuf(Fixed{Int32, 31}.(data), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        seek(io, 0)
        readbuf = loadwav(io)
        # convert 32-bit int buf to float, then to 16-bit, for testing
        @test readbuf == PCM16Sample.(Float32.(buf))
        @test framerate(readbuf) == 48000
        @test eltype(readbuf) == Fixed{Int16, 15}
    end
end
