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

# TODO: probably generalize to all units...
toindex(stream::SampleSource, t::SIQuantity) = round(Int, t*samplerate(stream)) + 1

# subtypes should only have to implement the `unsafe_read!` and `unsafe_write` methods, so
# here we implement all the converting wrapper methods

# when used as an amount of time to read, subtract one from the result of `toindex`
Base.read(stream::SampleSource, t::SIQuantity) = read(stream, toindex(stream, t)-1)

function Base.read(src::SampleSource, nframes::Integer)
    buf = SampleBuf(eltype(src), samplerate(src), nframes, nchannels(src))
    n = read!(src, buf)

    buf[1:n, :]
end

const DEFAULT_BUFSIZE=4096

# handle sink-to-source writing with a duration in seconds
function Base.write{T <: Real}(sink::SampleSink, source::SampleSource,
        duration::quantity(T, Second); bufsize=DEFAULT_BUFSIZE)
    sr = samplerate(sink)
    frames = trunc(Int, duration * sr)
    n = write(sink, source, frames; bufsize=bufsize)

    # if we completed the operation return back the original duration so the
    # caller can check equality to see if the operation succeeded
    n == frames ? duration : T(n/sr.val) * s
end

function Base.write(sink::SampleSink, source::SampleSource, frames=-1; bufsize=DEFAULT_BUFSIZE)
    if samplerate(sink) != samplerate(source)
        sink = ResampleSink(sink, samplerate(source), bufsize)
        # return write(srwrapper, source, bufsize)
    end

    if eltype(sink) != eltype(source)
        sink = ReformatSink(sink, eltype(source), bufsize)
        # return write(fmtwrapper, source, bufsize)
    end

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
    if nchannels(sink) != nchannels(buf)
        error("Channel count mismatch while writing buffer to sink")
    end
    if eltype(sink) != eltype(buf)
        error("Element Type mismatch while writing buffer to sink")
    end
    if samplerate(sink) != samplerate(buf)
        error("Sample rate mismatch while writing buffer to sink")
    end

    unsafe_write(sink, buf)
end

function Base.read!(source::SampleSource, buf::SampleBuf)
    if nchannels(source) != nchannels(buf)
        error("Channel count mismatch while reading sink to buffer")
    end
    if eltype(source) != eltype(buf)
        error("Element Type mismatch while reading sink to buffer")
    end
    if samplerate(source) != samplerate(buf)
        error("Sample rate mismatch while reading sink to buffer")
    end

    unsafe_read!(source, buf)
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

immutable ReformatSink{W <: SampleSink, B <: SampleBuf} <: SampleSink
    wrapped::W
    buf::B
end

function ReformatSink(wrapped::SampleSink, T, bufsize=DEFAULT_BUFSIZE)
    SR = samplerate(wrapped)
    WT = eltype(wrapped)
    N = nchannels(wrapped)
    buf = SampleBuf(WT, SR, bufsize, N)

    ReformatSink(wrapped, buf)
end

samplerate(sink::ReformatSink) = samplerate(sink.wrapped)
nchannels(sink::ReformatSink) = nchannels(sink.wrapped)
Base.eltype(sink::ReformatSink) = eltype(sink.wrapped)

function unsafe_write(sink::ReformatSink, buf::SampleBuf)
    bufsize = nframes(sink.buf)
    total = nframes(buf)
    written = 0

    while written < total
        n = min(bufsize, total - written)
        # copy to the buffer, which will convert to the wrapped type
        sink.buf[1:n, :] = sub(buf, (1:n) + written, :)
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

type ResampleSink{W <: SampleSink, U <: SIQuantity, B <: SampleBuf, A <: Array} <: SampleSink
    wrapped::W
    samplerate::U
    buf::B
    phase::Float64
    last::A
end

function ResampleSink(wrapped::SampleSink, SR::SIQuantity, bufsize=DEFAULT_BUFSIZE)
    WSR = samplerate(wrapped)
    T = eltype(wrapped)
    N = nchannels(wrapped)
    buf = SampleBuf(T, WSR, bufsize, N)

    ResampleSink(wrapped, SR, buf, 0.0, zeros(T, N))
end

# default sample rate unit to Hz
ResampleSink(wrapped, SR::Real, bufsize=DEFAULT_BUFSIZE) =
    ResampleSink(wrapped, SR*Hz, bufsize)

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

# TODO: bufsize should probably be a keyword arg, this positional argument
# should probably allow the user to limit how much is written.
