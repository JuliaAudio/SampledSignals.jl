"""
Represents a source of samples, such as an audio file or microphone input.

Subtypes should implement the `samplerate`, `nchannels`, `eltype`, and
`unsafe_read!` methods. `unsafe_read!` can assume that the samplerate, channel
count, and element type are all matching.
"""
abstract SampleSource

"""
unsafe_read!(source::SampleSource, buf::SampleBuf)

Reads samples from the given source to the given buffer, assuming that the
channel count, sampling rate, and element types are matching. This isn't called
from user code, but is called by the `read!` (and likewise `read`) implementions
in SampleTypes after it verifies that the buffer and sink are compatible, or
possibly adds a conversion wrapper.
"""
function unsafe_read! end

"""
Represents a sink that samples can be written to, such as an audio file or
headphone output.

Subtypes should implement the `samplerate`, `nchannels`, `eltype`, and
`unsafe_write` methods. `unsafe_write` can assume that the samplerate, channel
count, and element type are all matching.
"""
abstract SampleSink

"""
unsafe_write(sink::SampleSink, buf::SampleBuf)

Writes the given buffer to the given sink, assuming that the channel count,
sampling rate, and element types are matching. This isn't called from user code,
but is called by the `write` implemention in SampleTypes after it verifies that
the buffer and sink are compatible, or possibly adds a conversion wrapper.
"""
function unsafe_write end

toindex(stream::SampleSource, t::SIQuantity) = round(Int, t*samplerate(stream)) + 1

# subtypes should only have to implement the `unsafe_read!` and `unsafe_write` methods, so
# here we implement all the converting wrapper methods

# when used as an amount of time to read, subtract one from the result of `toindex`
Base.read(stream::SampleSource, t::SIQuantity) = read(stream, toindex(stream, t)-1)

function Base.read(src::SampleSource, nframes::Integer)
    buf = SampleBuf(eltype(src), samplerate(src), nframes, nchannels(src))
    # println("created buffer:\n$buf")
    n = read!(src, buf)

    buf[1:n, :]
end

const DEFAULT_BUFSIZE=4096

# handle sink-to-source writing with a duration in seconds
function Base.write{T <: Real}(sink::SampleSink, source::SampleSource,
        duration::quantity(T, Second); bufsize=DEFAULT_BUFSIZE)
    if SIUnits.unit(samplerate(sink)) != Hertz
        error("Specifying duration in seconds only supported with a sink samplerate in Hz")
    end
    sr = samplerate(sink)
    frames = trunc(Int, duration * sr)
    n = write(sink, source, frames; bufsize=bufsize)

    # if we completed the operation return back the original duration so the
    # caller can check equality to see if the operation succeeded. Note this
    # isn't going to be type-stable, but I don't expect this to be getting called
    # in a hot loop
    n == frames ? duration : n/sr
end

function Base.write(sink::SampleSink, source::SampleSource, frames=-1; bufsize=DEFAULT_BUFSIZE)
    if samplerate(sink) != samplerate(source)
        sink = ResampleSink(sink, samplerate(source), bufsize)
        # return write(srwrapper, source, bufsize)
    end

    # if eltype(sink) != eltype(source)
    #     sink = ReformatSink(sink, eltype(source), bufsize)
    #     # return write(fmtwrapper, source, bufsize)
    # end

    if nchannels(sink) != nchannels(source)
        if nchannels(sink) == 1
            sink = DownMixSink(sink, nchannels(source), bufsize)
            # return write(downwrapper, source, bufsize)
        elseif nchannels(source) == 1
            sink = UpMixSink(sink, bufsize)
            # return write(upwrapper, source, bufsize)
        else
            error("General M-to-N channel mapping not supported")
        end
    end
    # looks like everything matches, now we can actually hook up the source
    # to the sink
    unsafe_write(sink, source, frames, bufsize)
end

function unsafe_write(sink::SampleSink, source::SampleSource, frames=-1, bufsize=DEFAULT_BUFSIZE)
    written::Int = 0
    buf = SampleBuf(eltype(source), samplerate(source), bufsize, nchannels(source))
    while frames < 0 || written < frames
        n = frames < 0 ? bufsize : min(bufsize, frames - written)
        # this branch is just to avoid the allocation for the receive buffer
        if n < bufsize
            # TODO: add a frames parameter to unsafe_read! API so we don't need
            # to create a new buffer for this, or add subarray support
            buf = SampleBuf(eltype(source), samplerate(source), n, nchannels(source))
        end
        nr = unsafe_read!(source, buf)
        if nr < n
            # looks like the source stream is over. This currently allocates a
            # temporary buffer, so only do it when we need to
            nw = unsafe_write(sink, buf[1:nr, :])
            written += nw
            break
        end
        nw = unsafe_write(sink, buf)
        written += nw
        if nw < n
            # looks like the sink stream is closed
            break
        end
    end

    written
end

function Base.write(sink::SampleSink, buf::SampleBuf)
    if nchannels(sink) == nchannels(buf) &&
            eltype(sink) == eltype(buf) &&
            samplerate(sink) == samplerate(buf)
        unsafe_write(sink, buf)
    else
        # some conversion is necessary. Wrap in a source so we can use the
        # stream conversion machinery
        write(sink, SampleBufSource(buf))
    end
end

function Base.read!(source::SampleSource, buf::SampleBuf)
    if nchannels(source) == nchannels(buf) &&
            eltype(source) == eltype(buf) &&
            samplerate(source) == samplerate(buf)
        unsafe_read!(source, buf)
    else
        # println("doing conversion:")
        # println(nchannels(source), " --> ", nchannels(buf))
        # println(eltype(source), " --> ", eltype(buf))
        # println(samplerate(source), " --> ", samplerate(buf))
        # some conversion is necessary. Wrap in a sink so we can use the
        # stream conversion machinery
        write(SampleBufSink(buf), source)
    end
end

"""UpMixSink provides a single-channel sink that wraps a multi-channel sink.
Writing to this sink copies the single channel to all the channels in the
wrapped sink"""
immutable UpMixSink{W <: SampleSink, B <: SampleBuf} <: SampleSink
    wrapped::W
    buf::B
end

function UpMixSink(wrapped::SampleSink, bufsize=DEFAULT_BUFSIZE)
    N = nchannels(wrapped)
    SR = samplerate(wrapped)
    T = eltype(wrapped)
    buf = SampleBuf(T, SR, bufsize, N)

    UpMixSink(wrapped, buf)
end

samplerate(sink::UpMixSink) = samplerate(sink.wrapped)
nchannels(sink::UpMixSink) = 1
Base.eltype(sink::UpMixSink) = eltype(sink.wrapped)

function unsafe_write(sink::UpMixSink, buf::SampleBuf)
    bufsize = nframes(sink.buf)
    total = nframes(buf)
    written = 0

    while written < total
        n = min(bufsize, total - written)
        for ch in 1:nchannels(sink.wrapped)
            sink.buf[1:n, ch] = sub(buf, (1:n) + written)
        end
        # only slice if we have to
        if n == bufsize
            actual = unsafe_write(sink.wrapped, sink.buf)
        else
            actual = unsafe_write(sink.wrapped, sink.buf[1:n, :])
        end
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
immutable DownMixSink{W <: SampleSink, B <: SampleBuf} <: SampleSink
    wrapped::W
    buf::B
    channels::Int
end

function DownMixSink(wrapped::SampleSink, channels, bufsize=DEFAULT_BUFSIZE)
    SR = samplerate(wrapped)
    T = eltype(wrapped)
    buf = SampleBuf(T, SR, bufsize, 1)

    DownMixSink(wrapped, buf, channels)
end

samplerate(sink::DownMixSink) = samplerate(sink.wrapped)
nchannels(sink::DownMixSink) = sink.channels
Base.eltype(sink::DownMixSink) = eltype(sink.wrapped)

function unsafe_write(sink::DownMixSink, buf::SampleBuf)
    bufsize = nframes(sink.buf)
    total = nframes(buf)
    written = 0
    if nchannels(buf) == 0
        error("Can't do channel conversion from a zero-channel source")
    end

    while written < total
        n = min(bufsize, total - written)
        # initialize with the first channel
        sink.buf[1:n] = buf[(1:n) + written, 1]
        for ch in 2:nchannels(buf)
            sink.buf[1:n] += buf[(1:n) + written, ch]
        end
        # only slice if we have to
        if n == bufsize
            actual = unsafe_write(sink.wrapped, sink.buf)
        else
            actual = unsafe_write(sink.wrapped, sink.buf[1:n])
        end
        written += actual
        if actual != n
            # write stream closed early
            break
        end
    end

    written
end

# immutable ReformatSink{W <: SampleSink, B <: SampleBuf} <: SampleSink
#     wrapped::W
#     buf::B
# end
#
# function ReformatSink(wrapped::SampleSink, T, bufsize=DEFAULT_BUFSIZE)
#     SR = samplerate(wrapped)
#     WT = eltype(wrapped)
#     N = nchannels(wrapped)
#     buf = SampleBuf(WT, SR, bufsize, N)
#
#     ReformatSink(wrapped, buf)
# end
#
# samplerate(sink::ReformatSink) = samplerate(sink.wrapped)
# nchannels(sink::ReformatSink) = nchannels(sink.wrapped)
# Base.eltype(sink::ReformatSink) = eltype(sink.wrapped)
#
# function unsafe_write(sink::ReformatSink, buf::SampleBuf)
#     bufsize = nframes(sink.buf)
#     total = nframes(buf)
#     written = 0
#
#     while written < total
#         n = min(bufsize, total - written)
#         # copy to the buffer, which will convert to the wrapped type
#         sink.buf[1:n, :] = sub(buf, (1:n) + written, :)
#         # only slice if we have to
#         if n == bufsize
#             actual = unsafe_write(sink.wrapped, sink.buf)
#         else
#             actual = unsafe_write(sink.wrapped, sink.buf[1:n, :])
#         end
#         written += actual
#         if actual != n
#             # write stream closed early
#             break
#         end
#     end
#
#     written
# end

type ResampleSink{W <: SampleSink, U, B <: SampleBuf, A <: Array} <: SampleSink
    wrapped::W
    samplerate::U
    buf::B
    phase::Float64
    last::A
end

function ResampleSink(wrapped::SampleSink, SR, bufsize=DEFAULT_BUFSIZE)
    WSR = samplerate(wrapped)
    T = eltype(wrapped)
    N = nchannels(wrapped)
    buf = SampleBuf(T, WSR, bufsize, N)

    ResampleSink(wrapped, SR, buf, 0.0, zeros(T, N))
end

samplerate(sink::ResampleSink) = sink.samplerate
nchannels(sink::ResampleSink) = nchannels(sink.wrapped)
Base.eltype(sink::ResampleSink) = eltype(sink.wrapped)

function unsafe_write(sink::ResampleSink, buf::SampleBuf)
    bufsize = nframes(sink.buf)
    # we have to help inference here because SIUnits isn't type-stable on
    # division and multiplication
    # TODO: clean this when SIUnits is more type-stable
    ratio::Float64 = samplerate(sink) / samplerate(sink.wrapped)
    # total is in terms of samples at the wrapped sink rate
    total = trunc(Int, (nframes(buf) - 1) / ratio + sink.phase) + 1
    written::Int = 0

    nframes(buf) == 0 && return 0

    while written < total
        n = min(nframes(sink.buf), total-written)
        for i in 1:n
            bufidx = (written + i-1 - sink.phase)*ratio + 1
            leftidx = trunc(Int, bufidx)
            offset = bufidx - leftidx
            for ch in 1:nchannels(buf)
                left = leftidx == 0 ? sink.last[ch] : buf[leftidx, ch]
                sink.buf[i, ch] = (1-offset) * left + offset * buf[leftidx+1, ch]
            end
        end
        # only slice if we have to, to avoid allocating
        actual::Int
        if n == bufsize
            actual = unsafe_write(sink.wrapped, sink.buf)
        else
            actual = unsafe_write(sink.wrapped, sink.buf[1:n, :])
        end
        written += actual
        actual == n || break
    end

    # return the amount written in terms of the buffer's samplerate
    read = (written == total ? nframes(buf) : trunc(Int, written * ratio))
    read > 0 && (sink.last[:] = sub(buf, read, :))
    sink.phase = read / ratio + sink.phase - written

    read
end

"""SampleBufSource is a SampleSource backed by a buffer. It's mostly useful to
hook into the stream conversion infrastructure, because you can wrap a buffer in
a SampleBufSource and then write it into a sink with a different channel count,
sample rate, or channel count."""
type SampleBufSource{B<:SampleBuf} <: SampleSource
    buf::B
    read::Int
end

SampleBufSource(buf::SampleBuf) = SampleBufSource(buf, 0)

samplerate(source::SampleBufSource) = samplerate(source.buf)
nchannels(source::SampleBufSource) = nchannels(source.buf)
Base.eltype(source::SampleBufSource) = eltype(source.buf)

function unsafe_read!(source::SampleBufSource, buf::SampleBuf)
    n = min(nframes(buf), nframes(source.buf)-source.read)
    buf[1:n, :] = sub(source.buf, (1:n)+source.read, :)
    source.read += n

    n
end

"""SampleBufSink is a SampleSink backed by a buffer. It's mostly useful to
hook into the stream conversion infrastructure, because you can wrap a buffer in
a SampleBufSink and then read a source into it with a different channel count,
sample rate, or channel count."""
type SampleBufSink{B<:SampleBuf} <: SampleSink
    buf::B
    written::Int
end

SampleBufSink(buf::SampleBuf) = SampleBufSink(buf, 0)

samplerate(sink::SampleBufSink) = samplerate(sink.buf)
nchannels(sink::SampleBufSink) = nchannels(sink.buf)
Base.eltype(sink::SampleBufSink) = eltype(sink.buf)

function unsafe_write(sink::SampleBufSink, buf::SampleBuf)
    n = min(nframes(buf), nframes(sink.buf)-sink.written)
    sink.buf[(1:n)+sink.written, :] = sub(buf, 1:n, :)
    sink.written += n

    n
end
