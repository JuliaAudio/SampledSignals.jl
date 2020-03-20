import SignalBase
import SignalBase: framerate, nchannels
import SampledSignals: blocksize, unsafe_read!, unsafe_write
import Base: eltype

mutable struct DummySampleSource{T} <: SampleSource
    samplerate::Float64
    buf::Array{T, 2}
end

DummySampleSource(sr, buf::Array{T}) where T = DummySampleSource{T}(sr, buf)
SignalBase.framerate(source::DummySampleSource) = source.samplerate
SignalBase.nchannels(source::DummySampleSource) = size(source.buf, 2)
Base.eltype(source::DummySampleSource{T}) where T = T

function unsafe_read!(src::DummySampleSource, buf::Array, frameoffset, framecount)
    eltype(buf) == eltype(src) || error("buffer type ($(eltype(buf))) doesn't match source type ($(eltype(src)))")
    nchannels(buf) == nchannels(src) || error("buffer channel count ($(nchannels(buf))) doesn't match source channel count ($(nchannels(src)))")

    n = min(framecount, size(src.buf, 1))
    buf[(1:n) .+ frameoffset, :] = src.buf[1:n, :]
    src.buf = src.buf[(n+1):end, :]

    n
end


mutable struct DummySampleSink{T} <: SampleSink
    samplerate::Float64
    buf::Array{T, 2}
end

DummySampleSink(eltype, samplerate, channels) =
    DummySampleSink{eltype}(samplerate, Array{eltype}(undef, 0, channels))

SignalBase.framerate(sink::DummySampleSink) = sink.samplerate
SignalBase.nchannels(sink::DummySampleSink) = size(sink.buf, 2)
Base.eltype(sink::DummySampleSink{T}) where T = T

function SampledSignals.unsafe_write(sink::DummySampleSink, buf::Array,
                                     frameoffset, framecount)
    eltype(buf) == eltype(sink) || error("buffer type ($(eltype(buf))) doesn't match sink type ($(eltype(sink)))")
    nchannels(buf) == nchannels(sink) || error("buffer channel count ($(nchannels(buf))) doesn't match sink channel count ($(nchannels(sink)))")

    sink.buf = vcat(sink.buf, view(buf, (1:framecount) .+ frameoffset, :))

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
mutable struct BlockedSampleSource <: SampleSource
    framesleft::Int
end

blocksize(::BlockedSampleSource) = 16
SignalBase.framerate(::BlockedSampleSource) = 48.0
eltype(::BlockedSampleSource) = Float32
SignalBase.nchannels(::BlockedSampleSource) = 2

function unsafe_read!(src::BlockedSampleSource, buf::Array, frameoffset, framecount)
    @test framecount == blocksize(src)
    toread = min(framecount, src.framesleft)
    for ch in 1:nchannels(buf), i in 1:toread
        buf[i+frameoffset, ch] = i * ch
    end
    src.framesleft -= toread

    toread
end
