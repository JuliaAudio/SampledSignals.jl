"""
Represents a sample stream, which could be a physical device like a sound card,
or a network audio stream, audio file, etc.
"""
abstract SampleStream{N, SR, T}
abstract SampleSource{N, SR, T <: Real} <: SampleStream{N, SR, T}
abstract SampleSink{N, SR, T <: Real} <: SampleStream{N, SR, T}

# audio interface methods

samplerate{N, SR, T}(stream::SampleStream{N, SR, T}) = SR
nchannels{N, SR, T}(stream::SampleStream{N, SR, T}) = N
Base.eltype{N, SR, T}(stream::SampleStream{N, SR, T}) = T

# TODO: probably generalize to all units...
toindex(stream::SampleSource, t::RealTime) = round(Int, t.val*samplerate(stream)) + 1

# subtypes should only have to implement the `read!` and `write` methods, so
# here we implement all the converting wrapper methods

# when used as an amount of time to read, subtract one from the result of `toindex`
Base.read(stream::SampleSource, t::RealTime) = read(stream, toindex(stream, t)-1)

function Base.read{N, SR, T}(src::SampleSource{N, SR, T}, nframes::Integer)
    buf = SampleBuf(T, SR, nframes, nchannels(src))
    read!(src, buf)

    buf
end
