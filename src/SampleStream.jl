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

const DEFAULT_BUFSIZE=4096

function Base.write{N, SR, T}(sink::SampleSink{N, SR, T},
        source::SampleSource{N, SR, T},
        bufsize=DEFAULT_BUFSIZE)
    total = 0
    buf = SampleBuf(T, SR, bufsize, N)
    while true
        n = read!(source, buf)
        total += n
        if n < bufsize
            # this currently allocates a temporary buffer, so only do it when
            # we need to
            write(sink, buf[1:n, :])
            break
        end
        write(sink, buf)
    end
    
    total
end

# handle mono-to-mono, to disambiguate between mono-to-multi and multi-to-mono
# TODO: figure out how not to duplicate the above implementation
function Base.write{SR, T}(sink::SampleSink{1, SR, T},
        source::SampleSource{1, SR, T},
        bufsize=DEFAULT_BUFSIZE)
    total = 0
    buf = SampleBuf(T, SR, bufsize, 1)
    while true
        n = read!(source, buf)
        total += n
        if n < bufsize
            # this currently allocates a temporary buffer, so only do it when
            # we need to
            write(sink, buf[1:n])
            break
        end
        write(sink, buf)
    end
    
    total
end

# handle mono-to-multichannel conversion.
function Base.write{N, SR, T}(sink::SampleSink{N, SR, T},
        source::SampleSource{1, SR, T},
        bufsize=DEFAULT_BUFSIZE)

    total = 0
    monobuf = SampleBuf(T, SR, bufsize, 1)
    multibuf = SampleBuf(T, SR, bufsize, N)
    while true
        n = read!(source, monobuf)
        total += n
        for ch in 1:N
            multibuf[1:n, ch] = monobuf[1:n]
        end
        write(sink, multibuf[1:n, :])
        if n < bufsize
            break
        end
    end
    
    total
end

# handle multi-to-mono channel conversion.
function Base.write{N, SR, T}(sink::SampleSink{1, SR, T},
        source::SampleSource{N, SR, T},
        bufsize=DEFAULT_BUFSIZE)
    if N == 0
        error("Can't do channel conversion from a zero-channel source")
    end
    
    total = 0
    multibuf = SampleBuf(T, SR, bufsize, N)
    monobuf = SampleBuf(T, SR, bufsize, 1)
    while true
        n = read!(source, multibuf)
        total += n
        monobuf[1:n] = multibuf[1:n, 1]
        for ch in 2:N
            monobuf[1:n] += multibuf[1:n, ch]
        end
        write(sink, monobuf[1:n])
        if n < bufsize
            break
        end
    end
    
    total
end
