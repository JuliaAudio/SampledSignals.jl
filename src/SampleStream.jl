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
            sink.buf[1:n, ch] = sub(buf, (1:n) + written)
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

type ResampleSink{N, SR, T, W <: SampleSink, WSR} <: SampleSink{N, SR, T}
    wrapped::W
    buf::TimeSampleBuf{N, WSR, T}
    phase::Float64
    last::Array{T, 1}
end

function ResampleSink{W <: SampleSink}(wrapped::W, SR, bufsize=DEFAULT_BUFSIZE)
    WSR = samplerate(wrapped)
    T = eltype(wrapped)
    N = nchannels(wrapped)
    buf = SampleBuf(T, WSR, bufsize, N)

    ResampleSink{N, SR, T, W, WSR}(wrapped, buf, 0.0, zeros(T, N))
end

function Base.write{N, SR, T, W, WSR}(sink::ResampleSink{N, SR, T, W, WSR}, buf::SampleBuf{N, SR, T})
    bufsize = nframes(sink.buf)
    # total is in terms of samples at the wrapped sink rate
    ratio = SR / WSR
    total = trunc(Int, (nframes(buf) - 1) / ratio + sink.phase) + 1
    written::Int = 0

    nframes(buf) == 0 && return 0

    while written < total
        n = min(nframes(sink.buf), total-written)
        for i in 1:n
            bufidx = (written + i-1 - sink.phase)*ratio + 1
            leftidx = trunc(Int, bufidx)
            offset = bufidx - leftidx
            right = sub(buf, leftidx+1, :)
            # note we have to use `.*` here because devectorize doesn't recognize
            # that our multiplier is scalar. I don't think it makes a difference
            # though
            if leftidx == 0
                @devec sink.buf[i, :] = (1-offset) .* sink.last + offset .* right
            else
                left = sub(buf, leftidx, :)
                @devec sink.buf[i, :] = (1-offset) .* left + offset .* right
            end
        end
        actual::Int = write(sink.wrapped, sink.buf[1:n, :])
        written += actual
        actual == n || break
    end

    # return the amount written in terms of the buffer's samplerate
    read = (written == total ? nframes(buf) : trunc(Int, written * ratio))
    read > 0 && (sink.last[:] = sub(buf, read, :))
    sink.phase = read / ratio + sink.phase - written

    read
end

# TODO: bufsize should probably be a keyword arg, this positional argument
# should probably allow the user to limit how much is written.

function Base.write{N1, N2, SR1, SR2, T1, T2}(sink::SampleSink{N1, SR1, T1},
        source::SampleSource{N2, SR2, T2},
        bufsize=DEFAULT_BUFSIZE)

    if SR1 != SR2
        wrapper = ResampleSink(sink, SR2, bufsize)
        return write(wrapper, source, bufsize)
    end
    
    if T1 != T2
        wrapper = ReformatSink(sink, T2, bufsize)
        return write(wrapper, source, bufsize)
    end
    
    if N1 != N2
        if N1 == 1
            wrapper = DownMixSink(sink, N2, bufsize)
            return write(wrapper, source, bufsize)
        elseif N2 == 1
            wrapper = UpMixSink(sink, bufsize)
            return write(wrapper, source, bufsize)
        else
            error("General M-to-N channel mapping not supported")
        end
    end
    
    error("Couldn't write $(typeof(source)) to $(typeof(sink))")
end

# # handle mono-to-multichannel conversion.
# function Base.write{N, SR, T}(sink::SampleSink{N, SR, T},
#         source::SampleSource{1, SR, T},
#         bufsize=DEFAULT_BUFSIZE)
# 
#     wrapper = UpMixSink(sink, bufsize)
#     write(wrapper, source, bufsize)
# end
# 
# # handle multi-to-mono channel conversion.
# function Base.write{N, SR, T}(sink::SampleSink{1, SR, T},
#         source::SampleSource{N, SR, T},
#         bufsize=DEFAULT_BUFSIZE)
# 
#     wrapper = DownMixSink(sink, N, bufsize)
#     write(wrapper, source, bufsize)
# end
# 
# # handle stream format conversion
# function Base.write{N, SR, T1, T2}(sink::SampleSink{N, SR, T1},
#         source::SampleSource{N, SR, T2},
#         bufsize=DEFAULT_BUFSIZE)
# 
#     wrapper = ReformatSink(sink, T2, bufsize)
#     write(wrapper, source, bufsize)
# end
# 
# # handle sample rate conversion
# function Base.write{N, SR1, SR2, T}(sink::SampleSink{N, SR1, T},
#         source::SampleSource{N, SR2, T},
#         bufsize=DEFAULT_BUFSIZE)
# 
#     wrapper = ResampleSink(sink, SR2, bufsize)
#     write(wrapper, source, bufsize)
# end