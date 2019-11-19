"""
Represents a source of samples, such as an audio file, microphone input, or
SDR Receiver.

Subtypes should implement the `samplerate`, `nchannels`, `eltype`, and
`unsafe_read!` methods. `unsafe_read!` can assume that the samplerate, channel
count, and element type are all matching.
"""
abstract type SampleSource end

"""
unsafe_read!(source::SampleSource, buf::Array, frameoffset, framecount)

Reads samples from the given source to the given array, assuming that the
channel count, sampling rate, and element types are matching. This isn't called
from user code, but is called by the `read!` (and likewise `read`) implementions
in SampledSignals after it verifies that the buffer and sink are compatible, or
possibly adds a conversion wrapper. SampledSignals will call this method with
a 1D or 2D (nframes x nchannels) `Array`, with each channel in its own column.
`framecount` frames of data should be copied into the array starting at
`frameoffset+1`.
"""
function unsafe_read! end

"""
Represents a sink that samples can be written to, such as an audio file or
headphone output.

Subtypes should implement the `samplerate`, `nchannels`, `eltype`, and
`unsafe_write` methods. `unsafe_write` can assume that the samplerate, channel
count, and element type are all matching.
"""
abstract type SampleSink end

"""
unsafe_write(sink::SampleSink, buf::Array, frameoffset, framecount)

Writes the given buffer to the given sink, assuming that the channel count,
sampling rate, and element types are matching. This isn't called from user code,
but is called by the `write` implemention in SampledSignals after it verifies that
the buffer and sink are compatible, or possibly adds a conversion wrapper.
sampledsignals will call this method with a 1D or 2D (nframes x nchannels)
`Array`, with each channel in its own column. `framecount` frames of data should
be copied from the array starting at `frameoffset+1`.
"""
function unsafe_write end

# fallback functions for sources and sinks that don't have a preferred buffer
# size. This will cause any chunked writes to use the default buffer size
blocksize(src::SampleSource) = 0
blocksize(src::SampleSink) = 0

toindex(stream::SampleSource, t) = inframes(Int,t, samplerate(stream)) + 1

# subtypes should only have to implement the `unsafe_read!` and `unsafe_write` methods, so
# here we implement all the converting wrapper methods

# when used as an amount of time to read, subtract one from the result of `toindex`
Base.read(stream::SampleSource, t) = read(stream, toindex(stream, t)-1)

function Base.read(src::SampleSource, nframes::Integer)
    buf = SampleBuf(eltype(src), samplerate(src), nframes, nchannels(src))
    n = read!(src, buf)

    buf[1:n, :]
end

const DEFAULT_BLOCKSIZE=4096

# handle sink-to-source writing with a duration in seconds
function Base.write(sink::SampleSink, source::SampleSource, duration::Quantity;
                    blocksize=-1)
    sr = samplerate(sink)
    frames = trunc(Int, inseconds(duration, sr) * sr)
    n = write(sink, source, frames; blocksize=blocksize)

    # if we completed the operation return back the original duration so the
    # caller can check equality to see if the operation succeeded. Note this
    # isn't going to be type-stable, but I don't expect this to be getting called
    # in a hot loop
    n == frames ? duration : n/sr
end

# wraps the given sink to match the sampling rate and channel count of the source
# TODO: we should be able to add reformatting support to the ResampleSink and
# xMixSink types, to avoid an extra buffer copy
function wrap_sink(sink::SampleSink, source::SampleSource, blocksize)
    if eltype(sink) != eltype(source) && !isapprox(samplerate(sink), samplerate(source))
        # we're going to resample AND reformat. We prefer to resample
        # in the floating-point space because it seems to be about 40% faster
        if eltype(sink) <: AbstractFloat
            wrap_sink(ResampleSink(sink, samplerate(source), blocksize), source, blocksize)
        else
            wrap_sink(ReformatSink(sink, eltype(source), blocksize), source, blocksize)
        end
    elseif eltype(sink) != eltype(source)
        wrap_sink(ReformatSink(sink, eltype(source), blocksize), source, blocksize)
    elseif !isapprox(samplerate(sink), samplerate(source))
        wrap_sink(ResampleSink(sink, samplerate(source), blocksize), source, blocksize)
    elseif nchannels(sink) != nchannels(source)
        if nchannels(sink) == 1
            DownMixSink(sink, nchannels(source), blocksize)
        elseif nchannels(source) == 1
            UpMixSink(sink, blocksize)
        else
            error("General M-to-N channel mapping not supported")
        end
    else
        # everything matches, just return the sink
        sink
    end
end

function Base.write(sink::SampleSink, source::SampleSource, frames::FrameQuant;
                    blocksize=-1)
    write(sink, source, inframes(Int,frames,samplerate(source));
          blocksize=blocksize)
end
function Base.write(sink::SampleSink, source::SampleSource, frames=-1;
        blocksize=-1)
    if blocksize < 0
        blocksize = SampledSignals.blocksize(source)
    end
    if blocksize == 0
        blocksize = DEFAULT_BLOCKSIZE
    end
    # looks like everything matches, now we can actually hook up the source
    # to the sink
    unsafe_write(wrap_sink(sink, source, blocksize), source, frames, blocksize)
end

# internal function to wire up a sink and source, assuming they have the same
# sample rate and channel count
function unsafe_write(sink::SampleSink, source::SampleSource, frames=-1, blocksize=-1)
    written::Int = 0
    buf = Array{eltype(source)}(undef, blocksize, nchannels(source))
    while frames < 0 || written < frames
        n = frames < 0 ? blocksize : min(blocksize, frames - written)
        nr = unsafe_read!(source, buf, 0, n)
        nw = unsafe_write(sink, buf, 0, nr)
        written += nw
        if nr < n || nw < nr
            # one of the streams has reached its end
            break
        end
    end

    written
end

function Base.write(sink::SampleSink, buf::SampleBuf, nframes=nframes(buf))
    if nchannels(sink) == nchannels(buf) &&
            eltype(sink) == eltype(buf) &&
            isapprox(samplerate(sink), samplerate(buf))
        # everything matches, call the sink's low-level write method
        unsafe_write(sink, buf.data, 0, nframes)
    else
        # some conversion is necessary. Wrap in a source so we can use the
        # stream conversion machinery
        write(sink, SampleBufSource(buf), nframes)
    end
end

function Base.write(sink::SampleSink, buf::SampleBuf, duration::Quantity)
    n = inframes(Int, duration, samplerate(buf))
    written = write(sink, buf, n)
    if written == n
        return duration
    else
        return written / samplerate(buf) * s
    end
end

# treat bare arrays as a buffer with the same samplerate as the sink
function Base.write(sink::SampleSink, arr::Array, dur=nframes(arr))
    buf = SampleBuf(arr, samplerate(sink))
    write(sink, buf, dur)
end

function Base.read!(source::SampleSource, buf::SampleBuf, n::Integer)
    if nchannels(source) == nchannels(buf) &&
            eltype(source) == eltype(buf) &&
            isapprox(samplerate(source), samplerate(buf))
        unsafe_read!(source, buf.data, 0, n)
    else
        # some conversion is necessary. Wrap in a sink so we can use the
        # stream conversion machinery
        write(SampleBufSink(buf), source, n)
    end
end

# when reading into a SampleBuf, calculate frames based on the given buffer,
# which might differ from the source samplerate if there's a samplerate
# conversion involved.
function Base.read!(source::SampleSource, buf::SampleBuf, t)
    n = inframes(Int, t, samplerate(source))
    written = read!(source, buf, n)
    if written == n
        return t
    else
        return written / samplerate(buf) * s
    end
end

function Base.read!(source::SampleSource, buf::Array, t)
    n = inframes(Int, t, samplerate(source))
    written = read!(source, buf, n)
    if written == n
        return t
    else
        return written / samplerate(buf) * s
    end
end

# treat bare arrays as a buffer with the same samplerate as the source
function Base.read!(source::SampleSource, arr::Array, n::Integer)
    buf = SampleBuf(arr, samplerate(source))
    read!(source, buf, n)
end

# if no frame count is given default to the number of frames in the destination
Base.read!(source::SampleSource, arr::AbstractArray) = read!(source, arr, nframes(arr))

function Base.read(source::SampleSource)
    buf = SampleBuf(eltype(source),
                    samplerate(source),
                    DEFAULT_BLOCKSIZE,
                    nchannels(source))
    # during accumulation we keep the channels separate so we can grow the
    # arrays without needing to copy data around as much
    cumbufs = [Vector{eltype(source)}() for _ in 1:nchannels(source)]
    while true
        n = read!(source, buf)
        for ch in 1:length(cumbufs)
            append!(cumbufs[ch], @view buf.data[1:n, ch])
        end
        n == nframes(buf) || break
    end
    SampleBuf(hcat(cumbufs...), samplerate(source))
end

"""UpMixSink provides a single-channel sink that wraps a multi-channel sink.
Writing to this sink copies the single channel to all the channels in the
wrapped sink"""
struct UpMixSink{W <: SampleSink, B <: Array} <: SampleSink
    wrapped::W
    buf::B
end

function UpMixSink(wrapped::SampleSink, blocksize=DEFAULT_BLOCKSIZE)
    N = nchannels(wrapped)
    T = eltype(wrapped)
    buf = Array{T}(undef, blocksize, N)

    UpMixSink(wrapped, buf)
end

samplerate(sink::UpMixSink) = samplerate(sink.wrapped)
nchannels(sink::UpMixSink) = 1
Base.eltype(sink::UpMixSink) = eltype(sink.wrapped)
blocksize(sink::UpMixSink) = size(sink.buf, 1)

function unsafe_write(sink::UpMixSink, buf::Array, frameoffset, framecount)
    blksize = blocksize(sink)
    written = 0

    while written < framecount
        n = min(blksize, framecount - written)
        for ch in 1:nchannels(sink.wrapped)
            sink.buf[1:n, ch] = view(buf, (1:n) .+ written .+ frameoffset)
        end
        actual = unsafe_write(sink.wrapped, sink.buf, 0, n)
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
struct DownMixSink{W <: SampleSink, B <: Array} <: SampleSink
    wrapped::W
    buf::B
    channels::Int
end

function DownMixSink(wrapped::SampleSink, channels, blocksize=DEFAULT_BLOCKSIZE)
    T = eltype(wrapped)
    buf = Array{T}(undef, blocksize, 1)

    DownMixSink(wrapped, buf, channels)
end

samplerate(sink::DownMixSink) = samplerate(sink.wrapped)
nchannels(sink::DownMixSink) = sink.channels
Base.eltype(sink::DownMixSink) = eltype(sink.wrapped)
blocksize(sink::DownMixSink) = size(sink.buf, 1)

function unsafe_write(sink::DownMixSink, buf::Array, frameoffset, framecount)
    blocksize = nframes(sink.buf)
    written = 0
    if nchannels(buf) == 0
        error("Can't do channel conversion from a zero-channel source")
    end

    while written < framecount
        n = min(blocksize, framecount - written)
        # initialize with the first channel
        sink.buf[1:n] = buf[(1:n) .+ written .+ frameoffset, 1]
        for ch in 2:nchannels(buf)
            sink.buf[1:n] += buf[(1:n) .+ written .+ frameoffset, ch]
        end
        actual = unsafe_write(sink.wrapped, sink.buf, 0, n)
        written += actual
        if actual != n
            # write stream closed early
            break
        end
    end

    written
end

mutable struct ReformatSink{W <: SampleSink, B <: Array, T} <: SampleSink
    wrapped::W
    buf::B
    typ::T
end

function ReformatSink(wrapped::SampleSink, T, blocksize=DEFAULT_BLOCKSIZE)
    WT = eltype(wrapped)
    N = nchannels(wrapped)
    buf = Array{WT}(undef, blocksize, N)

    ReformatSink(wrapped, buf, T)
end

samplerate(sink::ReformatSink) = samplerate(sink.wrapped)
nchannels(sink::ReformatSink) = nchannels(sink.wrapped)
Base.eltype(sink::ReformatSink) = sink.typ
blocksize(sink::ReformatSink) = nframes(sink.buf)

function unsafe_write(sink::ReformatSink, buf::Array, frameoffset, framecount)
    blocksize = nframes(sink.buf)
    written = 0

    while written < framecount
        n = min(blocksize, framecount - written)
        # copy to the buffer, which will convert to the wrapped type
        sink.buf[1:n, :] = view(buf, (1:n) .+ written .+ frameoffset, :)
        actual = unsafe_write(sink.wrapped, sink.buf, 0, n)
        written += actual
        if actual != n
            # write stream closed early
            break
        end
    end

    written
end

mutable struct ResampleSink{W <: SampleSink, B <: Array, F <: FIRFilter} <: SampleSink
    wrapped::W
    samplerate::Float32
    buf::B
    ratio::Rational{Int}
    filters::Vector{F}
end

function ResampleSink(wrapped::SampleSink, sr, blocksize=DEFAULT_BLOCKSIZE)
    wsr = samplerate(wrapped)
    T = eltype(wrapped)
    N = nchannels(wrapped)
    buf = Array{T}(undef, blocksize, N)

    ratio = rationalize(wsr/sr)
    coefs = resample_filter(ratio)
    filters = [FIRFilter(coefs, ratio) for _ in 1:N]

    ResampleSink{typeof(wrapped), typeof(buf), eltype(filters)}(wrapped, sr, buf, ratio, filters)
end

samplerate(sink::ResampleSink) = sink.samplerate
nchannels(sink::ResampleSink) = nchannels(sink.wrapped)
Base.eltype(sink::ResampleSink) = eltype(sink.wrapped)
# TODO: implement blocksize for this

function unsafe_write(sink::ResampleSink, buf::Array, frameoffset, framecount)
    # check here for a zero-channel sink so we don't crash below
    nchannels(sink) < 1 && return framecount
    dest_blocksize = nframes(sink.buf)
    src_blocksize = trunc(Int, dest_blocksize / sink.ratio)

    written = 0
    while written < framecount
        towrite = min(src_blocksize, framecount - written)
        # good thing we checked for a zero-channel sink up there
        actual = filt!(view(sink.buf, :, 1),
                       sink.filters[1],
                       view(buf, (1:towrite) .+ written .+ frameoffset, 1))
        for ch in 2:nchannels(sink)
            if actual != filt!(view(sink.buf, :, ch),
                               sink.filters[ch],
                               view(buf, (1:towrite) .+ written .+ frameoffset, ch))
                error("Something went wrong - resampling channels out-of-sync")
            end
        end
        unsafe_write(sink.wrapped, sink.buf, 0, actual)
        written += towrite
    end

    written
end

"""SampleBufSource is a SampleSource backed by a buffer. It's mostly useful to
hook into the stream conversion infrastructure, because you can wrap a buffer in
a SampleBufSource and then write it into a sink with a different channel count,
sample rate, or channel count."""
mutable struct SampleBufSource{B<:SampleBuf} <: SampleSource
    buf::B
    read::Int
end

SampleBufSource(buf::SampleBuf) = SampleBufSource(buf, 0)

samplerate(source::SampleBufSource) = samplerate(source.buf)
nchannels(source::SampleBufSource) = nchannels(source.buf)
Base.eltype(source::SampleBufSource) = eltype(source.buf)

function unsafe_read!(source::SampleBufSource, buf::Array, frameoffset, framecount)
    n = min(framecount, nframes(source.buf)-source.read)
    buf[(1:n) .+ frameoffset, :] = view(source.buf, (1:n) .+ source.read, :)
    source.read += n

    n
end

"""SampleBufSink is a SampleSink backed by a buffer. It's mostly useful to
hook into the stream conversion infrastructure, because you can wrap a buffer in
a SampleBufSink and then read a source into it with a different channel count,
sample rate, or channel count."""
mutable struct SampleBufSink{B<:SampleBuf} <: SampleSink
    buf::B
    written::Int
end

SampleBufSink(buf::SampleBuf) = SampleBufSink(buf, 0)

samplerate(sink::SampleBufSink) = samplerate(sink.buf)
nchannels(sink::SampleBufSink) = nchannels(sink.buf)
Base.eltype(sink::SampleBufSink) = eltype(sink.buf)

function unsafe_write(sink::SampleBufSink, buf::Array, frameoffset, framecount)
    n = min(framecount, nframes(sink.buf)-sink.written)
    sink.buf[(1:n) .+ sink.written, :] = view(buf, (1:n) .+ frameoffset, :)
    sink.written += n

    n
end
