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
in SampledSignals after it verifies that the buffer and sink are compatible, or
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
but is called by the `write` implemention in SampledSignals after it verifies that
the buffer and sink are compatible, or possibly adds a conversion wrapper.
"""
function unsafe_write end

# fallback functions for sources and sinks that don't have a preferred buffer
# size. This will cause any chunked writes to use the default buffer size
blocksize(src::SampleSource) = 0
blocksize(src::SampleSink) = 0

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

const DEFAULT_BLOCKSIZE=4096

# handle sink-to-source writing with a duration in seconds
function Base.write{T <: Real}(sink::SampleSink, source::SampleSource,
        duration::quantity(T, Second); blocksize=-1)
    if SIUnits.unit(samplerate(sink)) != Hertz
        error("Specifying duration in seconds only supported with a sink samplerate in Hz")
    end

    sr = samplerate(sink)
    frames = trunc(Int, duration * sr)
    n = write(sink, source, frames; blocksize=blocksize)

    # if we completed the operation return back the original duration so the
    # caller can check equality to see if the operation succeeded. Note this
    # isn't going to be type-stable, but I don't expect this to be getting called
    # in a hot loop
    n == frames ? duration : n/sr
end

function Base.write(sink::SampleSink, source::SampleSource, frames=-1;
        blocksize=-1)
    if blocksize < 0
        blocksize = SampledSignals.blocksize(source)
    end
    if blocksize == 0
        blocksize = DEFAULT_BLOCKSIZE
    end
    if samplerate(sink) != samplerate(source)
        sink = ResampleSink(sink, samplerate(source), blocksize)
    end

    # if eltype(sink) != eltype(source)
    #     sink = ReformatSink(sink, eltype(source), blocksize)
    #     # return write(fmtwrapper, source, blocksize)
    # end

    if nchannels(sink) != nchannels(source)
        if nchannels(sink) == 1
            sink = DownMixSink(sink, nchannels(source), blocksize)
            # return write(downwrapper, source, blocksize)
        elseif nchannels(source) == 1
            sink = UpMixSink(sink, blocksize)
            # return write(upwrapper, source, blocksize)
        else
            error("General M-to-N channel mapping not supported")
        end
    end
    # looks like everything matches, now we can actually hook up the source
    # to the sink
    unsafe_write(sink, source, frames, blocksize)
end

function unsafe_write(sink::SampleSink, source::SampleSource, frames=-1, blocksize=-1)
    written::Int = 0
    buf = SampleBuf(eltype(source), samplerate(source), blocksize, nchannels(source))
    while frames < 0 || written < frames
        n = frames < 0 ? blocksize : min(blocksize, frames - written)
        # this branch is just to avoid the allocation for the receive buffer
        if n < blocksize
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

function UpMixSink(wrapped::SampleSink, blocksize=DEFAULT_BLOCKSIZE)
    N = nchannels(wrapped)
    SR = samplerate(wrapped)
    T = eltype(wrapped)
    buf = SampleBuf(T, SR, blocksize, N)

    UpMixSink(wrapped, buf)
end

samplerate(sink::UpMixSink) = samplerate(sink.wrapped)
nchannels(sink::UpMixSink) = 1
Base.eltype(sink::UpMixSink) = eltype(sink.wrapped)
blocksize(sink::UpMixSink) = size(sink.buf, 1)

function unsafe_write(sink::UpMixSink, buf::SampleBuf)
    blocksize = nframes(sink.buf)
    total = nframes(buf)
    written = 0

    while written < total
        n = min(blocksize, total - written)
        for ch in 1:nchannels(sink.wrapped)
            sink.buf[1:n, ch] = view(buf, (1:n) + written)
        end
        # only slice if we have to
        if n == blocksize
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

function DownMixSink(wrapped::SampleSink, channels, blocksize=DEFAULT_BLOCKSIZE)
    SR = samplerate(wrapped)
    T = eltype(wrapped)
    buf = SampleBuf(T, SR, blocksize, 1)

    DownMixSink(wrapped, buf, channels)
end

samplerate(sink::DownMixSink) = samplerate(sink.wrapped)
nchannels(sink::DownMixSink) = sink.channels
Base.eltype(sink::DownMixSink) = eltype(sink.wrapped)
blocksize(sink::DownMixSink) = size(sink.buf, 1)

function unsafe_write(sink::DownMixSink, buf::SampleBuf)
    blocksize = nframes(sink.buf)
    total = nframes(buf)
    written = 0
    if nchannels(buf) == 0
        error("Can't do channel conversion from a zero-channel source")
    end

    while written < total
        n = min(blocksize, total - written)
        # initialize with the first channel
        sink.buf[1:n] = buf[(1:n) + written, 1]
        for ch in 2:nchannels(buf)
            sink.buf[1:n] += buf[(1:n) + written, ch]
        end
        # only slice if we have to
        if n == blocksize
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
# function ReformatSink(wrapped::SampleSink, T, blocksize=DEFAULT_BLOCKSIZE)
#     SR = samplerate(wrapped)
#     WT = eltype(wrapped)
#     N = nchannels(wrapped)
#     buf = SampleBuf(WT, SR, blocksize, N)
#
#     ReformatSink(wrapped, buf)
# end
#
# samplerate(sink::ReformatSink) = samplerate(sink.wrapped)
# nchannels(sink::ReformatSink) = nchannels(sink.wrapped)
# Base.eltype(sink::ReformatSink) = eltype(sink.wrapped)
#
# function unsafe_write(sink::ReformatSink, buf::SampleBuf)
#     blocksize = nframes(sink.buf)
#     total = nframes(buf)
#     written = 0
#
#     while written < total
#         n = min(blocksize, total - written)
#         # copy to the buffer, which will convert to the wrapped type
#         sink.buf[1:n, :] = view(buf, (1:n) + written, :)
#         # only slice if we have to
#         if n == blocksize
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

function ResampleSink(wrapped::SampleSink, SR, blocksize=DEFAULT_BLOCKSIZE)
    WSR = samplerate(wrapped)
    T = eltype(wrapped)
    N = nchannels(wrapped)
    buf = SampleBuf(T, WSR, blocksize, N)

    sr_is_si = isa(SR, SIQuantity)
    wsr_is_si = isa(WSR, SIQuantity)
    if (wsr_is_si && !sr_is_si) || (!wsr_is_si && sr_is_si) ||
            (wsr_is_si && sr_is_si && SIUnits.unit(WSR) != SIUnits.unit(SR))
        error("Converting between units in samplerate conversion not yet supported")
    end

    ResampleSink(wrapped, SR, buf, 0.0, zeros(T, N))
end

samplerate(sink::ResampleSink) = sink.samplerate
nchannels(sink::ResampleSink) = nchannels(sink.wrapped)
Base.eltype(sink::ResampleSink) = eltype(sink.wrapped)
# TODO: implement blocksize for this

function unsafe_write(sink::ResampleSink, buf::SampleBuf)
    blocksize = nframes(sink.buf)
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
        local actual::Int
        if n == blocksize
            actual = unsafe_write(sink.wrapped, sink.buf)
        else
            actual = unsafe_write(sink.wrapped, sink.buf[1:n, :])
        end
        written += actual
        actual == n || break
    end

    # return the amount written in terms of the buffer's samplerate
    read = (written == total ? nframes(buf) : trunc(Int, written * ratio))
    read > 0 && (sink.last[:] = view(buf, read, :))
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
    buf[1:n, :] = view(source.buf, (1:n)+source.read, :)
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
    sink.buf[(1:n)+sink.written, :] = view(buf, 1:n, :)
    sink.written += n

    n
end
