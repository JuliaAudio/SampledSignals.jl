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

# TODO: this is totally duplicated from the more general N-to-N case, but
# necessary to disambiguiate between 1-to-N and N-to-1.
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

"""UpMixSink provides a single-channel sink that wraps a multi-channel sink.
Writing to this sink copies the single channel to all the channels in the
wrapped sink"""
immutable UpMixSink{N, SR, T, W <: SampleSink} <: SampleSink{1, SR, T}
    wrapped::W
    buf::TimeSampleBuf{N, SR, T}
end

function UpMixSink{W <: SampleSink}(wrapped::W, bufsize=DEFAULT_BUFSIZE)
    N = nchannels(wrapped)
    SR = samplerate(wrapped)
    T = eltype(wrapped)
    buf = SampleBuf(T, SR, bufsize, N)
    
    UpMixSink{N, SR, T, W}(wrapped, buf)
end

function Base.write{N, SR, T, W}(sink::UpMixSink{N, SR, T, W}, buf::SampleBuf{1, SR, T})
    bufsize = nframes(sink.buf)
    total = nframes(buf)
    written = 0
    
    while written < total
        n = min(bufsize, total - written)
        for ch in 1:N
            sink.buf[1:n, ch] = buf[(1:n) + written]
        end
        actual = write(sink.wrapped, sink.buf[1:n, :])
        written += actual
        if actual != n
            # write stream closed early
            break
        end
    end
    
    written
end

"""DownMixSink provides a multi-channel sink that wraps a single-channel sink.
Writing to this sink mixes all the channels down to the single channel"""
immutable DownMixSink{N, SR, T, W <: SampleSink} <: SampleSink{N, SR, T}
    wrapped::W
    buf::TimeSampleBuf{1, SR, T}
end

function DownMixSink{W <: SampleSink}(wrapped::W, channels, bufsize=DEFAULT_BUFSIZE)
    SR = samplerate(wrapped)
    T = eltype(wrapped)
    buf = SampleBuf(T, SR, bufsize, 1)
    
    DownMixSink{channels, SR, T, W}(wrapped, buf)
end

function Base.write{N, SR, T, W}(sink::DownMixSink{N, SR, T, W}, buf::SampleBuf{N, SR, T})
    bufsize = nframes(sink.buf)
    total = nframes(buf)
    written = 0
    if N == 0
        error("Can't do channel conversion from a zero-channel source")
    end
    
    while written < total
        n = min(bufsize, total - written)
        # initialize with the first channel
        sink.buf[1:n] = buf[(1:n) + written, 1]
        for ch in 2:N
            sink.buf[1:n] += buf[(1:n) + written, ch]
        end
        actual = write(sink.wrapped, sink.buf[1:n])
        written += actual
        if actual != n
            # write stream closed early
            break
        end
    end
    
    written
end

immutable ReformatSink{N, SR, T, W <: SampleSink, WT} <: SampleSink{N, SR, T}
    wrapped::W
    buf::TimeSampleBuf{N, SR, WT}
end

function ReformatSink{W <: SampleSink}(wrapped::W, T, bufsize=DEFAULT_BUFSIZE)
    SR = samplerate(wrapped)
    WT = eltype(wrapped)
    N = nchannels(wrapped)
    buf = SampleBuf(WT, SR, bufsize, N)
    
    ReformatSink{N, SR, T, W, WT}(wrapped, buf)
end

function Base.write{N, SR, T, W, WT}(sink::ReformatSink{N, SR, T, W, WT}, buf::SampleBuf{N, SR, T})
    bufsize = nframes(sink.buf)
    total = nframes(buf)
    written = 0
    
    while written < total
        n = min(bufsize, total - written)
        # copy to the buffer, which will convert to the wrapped type
        sink.buf[1:n, :] = buf[(1:n) + written, :]
        actual = write(sink.wrapped, sink.buf[1:n, :])
        written += actual
        if actual != n
            # write stream closed early
            break
        end
    end
    
    written
end

# handle mono-to-multichannel conversion.
function Base.write{N, SR, T}(sink::SampleSink{N, SR, T},
        source::SampleSource{1, SR, T},
        bufsize=DEFAULT_BUFSIZE)
    
    wrapper = UpMixSink(sink, bufsize)
    write(wrapper, source, bufsize)
end

# handle multi-to-mono channel conversion.
function Base.write{N, SR, T}(sink::SampleSink{1, SR, T},
        source::SampleSource{N, SR, T},
        bufsize=DEFAULT_BUFSIZE)
        
    wrapper = DownMixSink(sink, N, bufsize)
    write(wrapper, source, bufsize)
end

# handle stream conversion
function Base.write{N, SR, T1, T2}(sink::SampleSink{N, SR, T1},
        source::SampleSource{N, SR, T2},
        bufsize=DEFAULT_BUFSIZE)
        
    wrapper = ReformatSink(sink, T2, bufsize)
    write(wrapper, source, bufsize)
end