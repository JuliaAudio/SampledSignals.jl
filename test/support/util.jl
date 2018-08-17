import SampledSignals: blocksize, samplerate, nchannels
import Base: eltype

mutable struct DummySampleSource{R,T} <: SampleSource{R,T}
    buf::Array{T, 2}
end
DummySampleSource(sr, buf::Array{T}) where T =
  DummySampleSource{SampledSignals.format(sr),T}(buf)
nchannels(source::DummySampleSource) = size(source.buf, 2)
SampledSignals.nframes(source::DummySampleSource) = nframes(source.buf)

function Base.read!(src::DummySampleSource, buf::AbstractArray, ::IsSignal)
    if eltype(buf) != eltype(src)
      error("buffer type ($(eltype(buf))) doesn't match source "*
            "type ($(eltype(src)))")
    end
    if nchannels(buf) != nchannels(src)
      error("buffer channel count ($(nchannels(buf))) doesn't match source "*
            "channel count ($(nchannels(src)))")
    end

    n = min(nframes(buf), size(src.buf, 1))
    buf[1:n, :] = src.buf[1:n, :]
    src.buf = src.buf[(n+1):end, :]

    n
end


mutable struct DummySampleSink{R,T} <: SampleSink{R,T}
    buf::Array{T, 2}
end
function DummySampleSink(eltype, samplerate, channels)
  R = SampledSignals.format(samplerate)
  DummySampleSink{R, eltype}(Array{eltype}(undef, 0, channels))
end
nchannels(sink::DummySampleSink) = size(sink.buf, 2)

function Base.write(sink::DummySampleSink, buf::AbstractArray, ::IsSignal)
    if nchannels(buf) != nchannels(sink)
        error("buffer channel count ($(nchannels(buf))) doesn't match sink "*
              "channel count ($(nchannels(sink)))")
    end

    sink.buf = vcat(sink.buf, buf)

    nframes(buf)
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
mutable struct BlockedSampleSource{R,T} <: SampleSource{R,T}
    framesleft::Int
end
BlockedSampleSource(fl) = BlockedSampleSource{48.0Hz,Float32}(fl)
blocksize(::BlockedSampleSource) = 16
nchannels(::BlockedSampleSource) = 2

function Base.read!(src::BlockedSampleSource, buf::AbstractArray, ::IsSignal)
    @test nframes(buf) == blocksize(src)
    toread = min(nframes(buf), src.framesleft)
    for ch in 1:nchannels(buf), i in 1:toread
        buf[i, ch] = i * ch
    end
    src.framesleft -= toread

    toread
end
