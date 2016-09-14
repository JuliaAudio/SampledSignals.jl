import SampledSignals: blocksize, samplerate, nchannels, unsafe_read!, unsafe_write
import Base: eltype

type DummySampleSource{T, U} <: SampleSource
    samplerate::U
    buf::Array{T, 2}
end

samplerate(source::DummySampleSource) = source.samplerate
nchannels(source::DummySampleSource) = size(source.buf, 2)
Base.eltype{T, U}(source::DummySampleSource{T, U}) = T

function unsafe_read!(src::DummySampleSource, buf::Array, frameoffset, framecount)
    eltype(buf) == eltype(src) || error("buffer type ($(eltype(buf))) doesn't match source type ($(eltype(src)))")
    nchannels(buf) == nchannels(src) || error("buffer channel count ($(nchannels(buf))) doesn't match source channel count ($(nchannels(src)))")

    n = min(framecount, size(src.buf, 1))
    buf[(1:n)+frameoffset, :] = src.buf[1:n, :]
    src.buf = src.buf[(n+1):end, :]

    n
end


type DummySampleSink{T, U} <: SampleSink
    buf::Array{T, 2}
    samplerate::U
end

DummySampleSink(eltype, samplerate, channels) =
    DummySampleSink(Array(eltype, 0, channels), samplerate)

samplerate(sink::DummySampleSink) = sink.samplerate
nchannels(sink::DummySampleSink) = size(sink.buf, 2)
Base.eltype{T, U}(sink::DummySampleSink{T, U}) = T

function unsafe_write(sink::DummySampleSink, buf::Array, frameoffset, framecount)
    eltype(buf) == eltype(sink) || error("buffer type ($(eltype(buf))) doesn't match sink type ($(eltype(sink)))")
    nchannels(buf) == nchannels(sink) || error("buffer channel count ($(nchannels(buf))) doesn't match sink channel count ($(nchannels(sink)))")

    sink.buf = vcat(sink.buf, view(buf, (1:framecount)+frameoffset, :))

    framecount
end

# """
# Simulate receiving input on the dummy source This adds data to the internal
# buffer, so that when client code reads from the source they receive this data.
# """
# function simulate_input{N, SR, T}(src::DummySampleSource{N, SR, T}, data::Array{T})
#     if size(data, 2) != N
#         error("Simulated data channel count must match stream input count")
#     end
#     src.buf = vcat(src.buf, data)
# end

# stream interface methods

# used in SampleStream tests to test blocked reading
type BlockedSampleSource <: SampleSource
    framesleft::Int
end

blocksize(::BlockedSampleSource) = 16
samplerate(::BlockedSampleSource) = 48kHz
eltype(::BlockedSampleSource) = Float32
nchannels(::BlockedSampleSource) = 2

function unsafe_read!(src::BlockedSampleSource, buf::Array, frameoffset, framecount)
    @test framecount == blocksize(src)
    toread = min(framecount, src.framesleft)
    for ch in 1:nchannels(buf), i in 1:toread
        buf[i+frameoffset, ch] = i * ch
    end
    src.framesleft -= toread

    toread
end
