"""
Represents a source of samples, such as an audio file, microphone input, or
SDR Receiver, using sample rate `R` and eltype `T`. The rate is assumed
to be specified in units compatible with `Hz`.

Subtypes should implement the `nchannels` and a specific `read!` method,
described below.  Optionally it can also implement `nframes`, `blocksize`
and `tosamplerate`, which all have default implementations.

The read! method should take the following form.

    Base.read!(source::SampleSource{R}, buf::AbstractArray, ::IsSignal{R})

This internal method will be called after `buf` and `source` have been coerced
to have the same sample rate and channel count. This call is expected to fill
the entire contents of `buf` with samples, unless there are fewer samples
available than `nframes(buf)`. The total number of samples successfully read
from `source` should be returned.

NOTE: you can implement `tosamplerate` if there is some efficient way to
compute more samples with a new sample rate rather than signal
interpolation via FFT (the default approach).
"""
abstract type SampleSource{R,T} end
SignalFormat(x::SampleSource{R,T}) where {R,T} = IsSignal{R,T}()
Base.eltype(x::SampleSource{<:Any,T}) where T = T
Base.eltype(::Type{<:SampleSource{<:Any,T}}) where T = T
nframes(::SampleSource) = missing
blocksize(::SampleSource) = missing

function Base.read!(source::SampleSource{R}, buf::AbstractArray,
                    ::IsSignal{R}) where {R}
    error("No appropriate implementation of `read!` for $(typeof(source)).",
          " Define a signature of the form ",
          "`Base.read!(source::SampleSource{R},buf::AbstractArray,",
          "::IsSignal{R})`.")
end

"""
Represents a sink that samples can be written to, such as an audio file or
headphone output, using samplerate `R` and eltype `T`. The rate is assumed
to be specified in units compatible with `Hz`.

Subtypes should implement the `nchannels`, and `write` methods.  The
Optionally it can also implement `nframes` and `blocksize`.

The `write` method should take the following form.

    Base.write(sink::SampleSink{R}, buf::AbstractArray, ::IsSignal{R})

This internal method will be called after `buf` and `source` have the same
sample rate and channel count. This call should send the entire contents of
`buf` to `sink`, unless there are fewer samples that can be written to `sink`
than `nframes(buf)`. The total number of samples successfully written to `sink`
should be returned.

Note that raw `Array` objects and other types that do not have a known sample
rate are assumed to have the same sample rate as `source`. The `eltype` may
differ between `source` and `buf`.

"""
abstract type SampleSink{R,T} end
SignalFormat(x::SampleSink{R,T}) where {R,T} = IsSignal{R,T}()
Base.eltype(x::SampleSink{R,T}) where {R,T} = T
Base.eltype(::Type{<:SampleSink{<:Any,T}}) where T = T
blocksize(::SampleSink) = missing
nframes(::SampleSink) = missing

function Base.write(sink::SampleSink{R}, buf::AbstractArray,
                    ::IsSignal{R}) where R
    error("No appropriate implementation of `write!` for $(typeof(sink)).",
          " Define a signature of the form ",
          "`Base.write(sink::SampleSink{R},buf::AbstractArray,",
          "::IsSignal{R})`.")
end

# fallback functions for sources and sinks that don't have a preferred buffer
# size. This will cause any chunked writes to use the default buffer size
"""
    blocksize(x)

Returns the preferred block size of the sampled sink or source. Only implement
this method if there is a particular size that is more efficient for the sink
or source. If no particular size is necessary, to indicate this the default
fall-back method returns missing.
"""
function blocksize end
const DEFAULT_BLOCKSIZE=4096

########################################
# read methods
function Base.read(src::SampleSource,
                   len=coalesce(nframes(src),blocksize(src),DEFAULT_BLOCKSIZE))
    nframes = inframes(Int,len,usamplerate(src))
    if nchannels(src) > 1
        buf = SampleBuf(eltype(src), usamplerate(src), nframes, nchannels(src))
    else
        buf = SampleBuf(eltype(src), usamplerate(src), nframes)
    end
    n = read!(src, buf)

    if ndims(buf) > 1
        buf[1:n, :]
    else
        buf[1:n]
    end
end

function Base.read!(src::SampleSource, buf::AbstractArray, len=nframes(buf))

    checkformat(src)
    frames = inframes(Int,len,usamplerate(src))
    n = write(SampleBufSink(signal(buf,usamplerate(src))), src, frames)
    sameunits(len,nframes,n,usamplerate(src))
end

sameunits(len::Unitful.Time,nframes,n,sr) =
    nframes == n ? len : inseconds(n*frames,sr)*s
sameunits(len,nframes,n,sr) = n

########################################
# write methods

Base.write(sink::SampleSink, source, frames=nothing;kwds...) =
    write(sink,tosource(signal(source,usamplerate(sink))),frames;kwds...)

function Base.write(sink::SampleSink, source::SampleSource, len=nothing;
                    blocksize=coalesce(SampledSignals.blocksize(source),
                                       DEFAULT_BLOCKSIZE))
    checkformat(sink)
    checkformat(source)

    nframes = len==nothing ? nothing :
        trunc(Int,inframes(len,usamplerate(source)))

    n = write_helper(sink, promote_signal(source,by=sink), nframes, blocksize)
    sameunits(len,nframes,n,usamplerate(sink))
end

# internal function to wire up a sink and source, assuming they have the same
# sample rate and channel count
function write_helper(sink::SampleSink{R}, source::SampleSource{R},
                      frames, blocksize) where R
    written::Int = 0
    buf = Array{eltype(source)}(undef, blocksize, nchannels(source))
    while frames == nothing || written < frames
        n = frames == nothing ? blocksize : min(blocksize, frames - written)
        nr = read!(source, view(buf,1:n,:), SignalFormat(source))
        nw = write(sink, view(buf,1:nr,:), SignalFormat(source))
        written += nw
        if nr < n || nw < nr
            # one of the streams has reached its end
            break
        end
    end

    written
end

########################################
# sink coercion: all coercion is handled by changing the sample rate and
# channels of the sink (see write and read above).  to coerce source they are
# first interpreted as sinks

function tosamplerate(sink::SampleSource,S,::IsSignal{R}) where {R}
    if dimension(S) != dimension(R)
        error("Changing the dimension of a stream from $(dimension(S)) to ",
              "$(dimension(R)) is not supported.")
    elseif !isapprox(S,R)
        ResampleSource(sink, S)
    else
        sink
    end
end
tochannels(sink::SampleSource,ch) = ChannelMixSource(sink,ch)

# simple coercion of sinks (everything but sample rate)
# using SampleBuf coercion

struct ChannelMixSource{Dir,R,T,W<:SampleSource} <: SampleSource{R,T}
    wrapped::W
    ch::Int
end
function ChannelMixSource(wrapped::SampleSource{R,T}, ch) where {R,T}
    dir = if nchannels(wrapped) == 1
      :down
    elseif ch == 1
      :up
    else
      error("Don't know how to coerce a $(nchannels(x))-channel stream",
            " to have $ch channels.")
    end
    ChannelMixSource{dir,R,T,typeof(wrapped)}(wrapped,ch)
end
nchannels(x::ChannelMixSource) = x.ch
tochannels(x::ChannelMixSource,ch) = ChannelMixSource(x.wrapped,ch)
function Base.read!(source::ChannelMixSource{:down,R}, buf::AbstractArray,
                    trait::IsSignal{R}) where R
  n = read!(source.wrapped,view(buf,:,1),trait)
  buf[1:n,2:end] .= view(buf,1:n,1)
  n
end
function Base.read!(source::ChannelMixSource{:up,R}, buf::AbstractArray,
                    trait::IsSignal{R}) where R
  unmixed = Array{eltype(buf)}(undef, nframes(buf), nchannels(source.wrapped))
  n = read!(source.wrapped, unmixed, trait)
  sum!(view(buf,1:n,:),view(unmixed,1:n,:))
  n
end

mutable struct ResampleSource{R, T, W <: SampleSource, B <: Array,
                              L, FIR <: FIRFilter} <: SampleSource{R,T}
    wrapped::W
    buf::B
    ratio::Rational{Int}
    filters::Vector{FIR}
    leftover::L
    leftover_range::UnitRange{Int}
end
# coercion of sample rate
function ResampleSource(wrapped::SampleSource, sr,
                        blocksize=coalesce(SampledSignals.blocksize(wrapped),
                                           DEFAULT_BLOCKSIZE))

    ratio = rationalize(uconvert(Unitful.NoUnits,sr/usamplerate(wrapped)))

    wsr = samplerate(wrapped)
    T = eltype(wrapped)
    N = nchannels(wrapped)
    buf = Array{T}(undef, trunc(Int,blocksize*ratio), N)

    coefs = resample_filter(ratio)
    filters = [FIRFilter(coefs, ratio) for _ in 1:N]

    R = format(sr)
    W = typeof(wrapped)
    B = typeof(buf)
    FIR = eltype(filters)

    leftover = zeros(T, max(2,ceil(Int,ratio)), nchannels(wrapped))
    L = typeof(leftover)
    ResampleSource{R, T, W, B, L, FIR}(wrapped, buf, ratio, filters,
                                       leftover, 1:0)
end
blocksize(x::ResampleSource) = trunc(Int,nfrmaes(x.buf) * x.ratio)
nchannels(source::ResampleSource) = nchannels(source.wrapped)
tosamplerate(source::ResampleSource,R,::IsSignal) =
  tosamplerate(source.wrapped,R)
function tochannels(source::ResampleSource,ch)
  # do the channel mixing in the most efficient order (to minimize the number
  # of resampling operations required)
  if ch < nchannels(source)
    tosamplerate(ChannelMixSource(source.wrapped,ch),usamplerate(source))
  else
    ChannelMixSource(source,ch)
  end
end
function Base.read!(source::ResampleSource{R}, buf::AbstractArray,
                    trait::IsSignal{R}) where R
    nchannels(buf) > 0 || return nframes(buf)
    tosr(x) = ceil(Int,x * source.ratio)
    fromsr(x) = trunc(Int,x / source.ratio)

    n = 0
    trait = IsSignal{usamplerate(source.wrapped), eltype(source.buf)}()
    while n < nframes(buf)
        # if there are samples leftover from a previous read,
        # write them to the buffer
        if length(source.leftover_range) > 0
            buf[(1:length(source.leftover_range)) .+ n,:] =
                view(source.leftover,source.leftover_range,:)
            n += length(source.leftover_range)
            source.leftover_range = 1:0
        end

        toread = max(1,min(fromsr(nframes(buf)) - n,tosr(nframes(source.buf))))
        actual_wrapped = read!(source.wrapped, view(source.buf,1:toread,:),
                               trait)

        actual_wrapped > 0 || break
        actual_resamp = actual_ch = 0
        for ch in 1:nchannels(buf)
            # good thing we checked for a zero-channel source up there
            tofilt = min(nframes(buf)-n,tosr(actual_wrapped))
            # we might have to save some samples in `leftover` if `filt!` will
            # produce more samples than we want to read.
            if tofilt < tosr(actual_wrapped)
                actual_ch = filt!(view(source.leftover,:,ch),
                                        source.filters[ch],
                                        view(source.buf,1:actual_wrapped,ch))
                actual_fill = min(actual_ch,tofilt)
                buf[(1:actual_fill) .+ n,ch] =
                    view(source.leftover,1:actual_fill,ch)
                source.leftover_range = (actual_fill+1):actual_ch
                actual_ch = actual_fill
            else
                actual_ch = filt!(view(buf,(1:tofilt) .+ n,ch),
                                  source.filters[ch],
                                  view(source.buf,1:actual_wrapped,ch))
            end

            if ch == 1
                actual_resamp = actual_ch
            elseif actual_resamp != actual_ch
                error("Something went wrong - resampling channels out-of-sync")
            end
        end
        n += actual_resamp
    end

    return n
end

########################################
# coerce objects into sources

"""
    tosource(x,::IsSignal)

Internal method used by `mapsignals`: if a signal isn't an `AbstractArray` it
must implement this to be used in `mapsignals`. The method for a new signal
type should always return a `SampleSource` object.
"""
tosource(x::SampleBuf) = ArrayLikeSource(x)
tosource(x::SampleSource) = x
tosource(x) = tosource(x,SignalFormat(x))
tosource(x::AbstractArray,::IsSignal) = ArrayLikeSource(x)
tosource(x,::IsSignal) =
    error("Don't know how to read from signal $x. ",
          "Implement `tosource(x::$(typeof(x)),::IsSignal)`.")
tosource(x,::NotSignal) = error("$x is not a signal.")

signal(x::Number,R,::NotSignal) = SingletonSource{format(R),typeof(x)}(x,1)
struct SingletonSource{R,T} <: SampleSource{R,T}
    num::T
    ch::Int
end
nchannels(x::SingletonSource) = 1
tosamplerate(x::SingletonSource,sr,::IsSignal) = signal(x.num,sr)
tochannels(x::SingletonSource{R,T},ch) where {R,T} =
    SingletonSource{R,T}(x.num,ch)
function Base.read!(source::SingletonSource{R}, buf::AbstractArray,
                    ::IsSignal{R}) where R
    buf .= source.num
    nframes(buf)
end

# TODO: can this be any signal that's an array our just a SampleBuf?
"""
ArrayLikeSource is a SampleSource backed by an array. It's used to handle
interactions between any signal that satisfies the `AbstractArray` interface
(including `SampleBuf` objects) and SampleSource objects in a uniform way.
"""
mutable struct ArrayLikeSource{B,R,T} <: SampleSource{R,T}
    buf::B
    read::Int
end
ArrayLikeSource(buf) = ArrayLikeSource(buf,SignalFormat(buf))
ArrayLikeSource(buf,::IsSignal{R,T}) where {R,T} =
    ArrayLikeSource{typeof(buf),R,T}(buf, 0)
nchannels(source::ArrayLikeSource) = nchannels(source.buf)
nframes(source::ArrayLikeSource) = nframes(source.buf)
blocksize(source::ArrayLikeSource) = nframes(source.buf)
function Base.read!(source::ArrayLikeSource{<:Any,R}, buf::AbstractArray,
                    ::IsSignal{R}) where R
    n = min(nframes(buf), nframes(source.buf)-source.read)
    buf[(1:n), :] = view(source.buf, (1:n) .+ source.read, :)
    source.read += n

    n
end
function tosamplerate(x::ArrayLikeSource,sr,::IsSignal{R}) where R
    if sr != R
        tosource(tosamplerate(x.buf[x.read+1:end,:],sr))
    else
        x
    end
end

"""
SampleBufSink is a SampleSink backed by a buffer. It's used to handle
writing to a SampleBuf from a set of SampleSource objects.
"""
mutable struct SampleBufSink{B<:SampleBuf,R,T} <: SampleSink{R,T}
    buf::B
    written::Int
end
SampleBufSink(buf::SampleBuf{<:Any,R,T}) where {R,T} =
    SampleBufSink{typeof(buf),R,T}(buf, 0)
nchannels(sink::SampleBufSink) = nchannels(sink.buf)
blocksize(buf::SampleBufSink) = nframes(sink.buf)
function Base.write(sink::SampleBufSink{<:Any,R}, buf::AbstractArray,
                    ::IsSignal{R}) where R
    n = min(nframes(buf), nframes(sink.buf)-sink.written)
    sink.buf[(1:n) .+ sink.written, :] = view(buf, (1:n), :)
    sink.written += n

    n
end

########################################
# function -> signal
mutable struct FnSource{Fn,R,T} <: SampleSink{R,T}
    fn::Fn
    freq2pi::Float64
    ϕ::Float64
end

"""
    signal(fn,freq,eltype=Float64;phase=0,ϕ=phase,samplerate=48000)

Generate an infinite mono signal (a `SampleSource`) with the given eltype. In
other ways this works in exactly the way generating finite signals with
`signal` does.

For example, the following creates an arbitrary length pure tone at
1000 Hz.

signal(sin,1kHz)

"""
function signal(fn::Function,freq,eltype::Type{T}=Float64;phase=0,ϕ=phase,
                samplerate=48kHz) where T
    ratio = inHz(freq) / inHz(samplerate)
    FnSource{typeof(fn),usamplerate(sr),T}(fn,2π * ratio,ϕ)
end
nchannels(::FnSource) = 1
function Base.read!(source::FnSource{<:Any,R}, buf::AbstractArray,
                    ::IsSignal{R}) where R
    br = eltype(F)
    ϕ = 1:nframes(buf).*source.freq2pi .+ source.ϕ
    buf[1:nframes(buf)] .= br.(fn.(ϕ))
    source.ϕ += last(ϕ)

    nframes(buf)
end
function tosamplerate(x::FnSource{Fn,R,T},sr,::IsSignal{R}) where {Fn,R,T}
    ratio = inHz(R) / inHz(sr)
    FnSource{Fn,sr,T}(x.fn,x.freq2pi * ratio ,x.ϕ)
end

struct SampleSourceByFn{Fn,R,T} <: SampleSource{R,T}
    fn::Fn
    ch::Int
end
nchannels(x::SampleSourceByFn) = x.ch
function Base.read!(source::SampleSourceByFn{<:Any,R}, buf::AbstractArray,
                    ::IsSignal{R}) where R
    source.fn(buf)
end

"""
    stream(fn,eltype=Float64;samplerate=48kHz,nchannels=1)

Creates `SampleSource` object of the given format, from a single function.  The
function should write as many frames into its single argument (an
`AbstractArray`) and return the number of frames successfully written.
"""
function stream(fn::Function,eltype::Type{T}=Float64;samplerate=48kHz,
                nchannels=1) where T

    SampleSourceByFn{typeof(fn),format(samplerate),T}(fn,nchannels)
end

########################################
# flexible mapping that pads missing samples

"""
    mapsignals(f,xs...;pad=[usually 0], blocksize=[default varies, see below])

Analogous to `broadcast`, applies `f` to each sample across all the signals.
The key difference from `broadcast` is that `mapsignals` first coerces all of
the signals to the same sample rate and then pads any missing samples at the
end of signals to match the longest one. Any object that can be interpreted as
a signal (e.g. `Number` or `AbstractArray`) using the `signal` method can also
be passed.  Non-signals are assumed to be at the highest sample rate passed.
You can interpret an array to be at a different, explicit sample rate by
passing it to `signal` first. Returns either a `SampleBuf` if all of the
inputs are numbers or `AbstractArray` objects (includes `SampleBuf`), otherwise
a `SampleStream`.

NOTE: The `eltype` of the result is inferred from the first call to `f`.  This
means that if the type of the return value of `f` changes sometime later, it
will be coerced to be the same type as prior outputs.

# Keyword arguments:

## Blocksize

The block size is set to a sensible default and need not normally be configured.

When all inputs are of known lengths (e.g. any `AbstractArray` or `Number`) the
block size will be set to the longest length signal. It is not recommended to
change the `blocksize` in this case. For streams the block size will be set to
the minimum `blocksize` of the inputs.

# Padding

Padding determines what value to pass to `f` once the end of a signal
is reached.  Available padding functions are `padlast`, `padcycle` and
`padzero`.

## Padding

Padding can be a specific number, one of the predefined padding functions
(`padzero`, `padlast` or `padcycle`) or a custom function (see below).

By default, padding is determined by the mapping function `f`, and normally
defaults to `padzero`. If `f` is `*` or '/` the default is `padlast`. You can
pass a different padding with the `pad` keyword or you can indicate that
a different padding should be used by default for mapping funciton `f` by
defining

    SampledSignals.padding(::typeof(f)) = [padding function here]

### Custom Padding

Custom padding functions should take the same functional form as `getindex` and
will be passed an `AbstractArray` and the invalid indices for each signal.

There are several properties assumed about a custom padding function by
default. These can be changed for faster performance or to make the function
usuable in more situations.

#### Padding a signal of an unknown length is an error by default.

By default it is assumed that a custom padding function may access any valid
index of the passed array: therefore an error will be thrown if the padding
function is passed a signal with an unknown length such as a `SampleSource`. To
support signals with an unknown length for function `padfn`, you can declare
the following.

    SampledSignals.pad_stream(::typeof(padfn)) = true

When implementing such a function, keep in mind that `padfn` may not be passed
the entire signal and the index will reference the start of the passed array
not the start of the signal: when operating over `SampleSource` objects, this
passed array is at most `blocksize` in length, and may be shorter.

#### The padding output may vary across indices.

It is normally assumed a different padding value might be used for different
indices past the end of a signal. To further optimize a padding function you
can indicate that its result only depends on the array input (1st argument) and
not any of the indexing arguments. If you wish to indicate otherwise, declare
the following.

    SampleSignals.pad_index_constant(::typeof(padfn)) = true

The function will only be called once for each signal rather than for each
index of the array past the end of the signal that is needed.

#### The padding function requires at least one valid index.

It is normally assumed that the padding function will require the input
array to have at least one valid index (`a[1]`). If the padding function
can safely return a result even when the array is empty, you can define
the following.

    SampledSignals.pad_empty_array(::typeof(padfn)) = true

"""
mapsignals(f;kwds...) = error("No signals passed to `mapsignals`.")
mapsignals(f,xs::Number...;kwds) = f(xs...)
function mapsignals(f,xs...;blocksize=nothing,kwds...)
    signals = promote_signals(xs...)
    MappedSource(f,signals...;blocksize=findblocksize(xs,blocksize),kwds...)
end
mapsignal_len(x::Number) = 0
mapsignal_len(x::AbstractArray) = nframes(x)
function mapsignals(f,xs::Union{AbstractArray,Number}...;blocksize=nothing,
                    kwds...)
    signals = promote_signals(xs...)
    len = maximum(mapsignal_len.(xs))
    result = MappedSource(f,signals...; blocksize=len, kwds...)
    read(result,len)
end
function findblocksize(xs,blocksize)
  if blocksize==nothing
    sizes = skipmissing(SampledSignals.blocksize.(xs))
    if isempty(sizes)
      DEFAULT_BLOCKSIZE
    else
      minimum(sizes)
    end
  else
    blocksize
  end
end

nframes_helper(::Number) = missing
nframes_helper(x) = nframes(x)

"""
    mapsignals!(f,result,xs...;pad=SampleSource.padding(f))

Like `mapsignals` but stores the result in `result`.
"""
function mapsignals!(f,result::SampleSink,xs...;kwds...)
    write(result,mapsignals(f,xs...;kwds...))
end
mapsignals!(f,result,xs...;kwds...) =
    mapsignals(f,result,SignalFormat(result),xs...;kwds...)
function mapsignals!(f,result,::NotSignal,xs...;kwds...)
    xs = promote_signals(xs...)
    mapsignals(f,signal(result,usamplerate(xs[1])),xs...;kwds...)
end
function mapsignals!(f,result::AbstractArray,::IsSignal,
                     xs::Union{Number,AbstractArray}...; kwds...)
    source = MappedSource(f,promote_signal.(xs,by=result);kwds...)
    write(SampleBufSink(result), source, nframes(result))
end
padding(x) = padzero
padding(::typeof(*)) = padlast
padding(::typeof(/)) = padlast
pad_stream(x) = false
pad_empty_array(x) = false
pad_index_constant(x) = false
pad_stream(::Number) = true
pad_empty_array(::Number) = true
apply_pad(pad,x,ixs...) = pad(x,i)
apply_pad(pad::Number,x,ixs...) = pad

"""
    padzero(x,ixs...)

Pads indices with `zero(eltype(x))`. See `mapsignals`.
"""
@Base.propagate_inbounds padzero(x,ixs...) = zero(eltype(x))
pad_stream(::typeof(padzero)) = true
pad_index_constant(::typeof(padzero)) = true

"""
    padlast(x,ixs...)

Pads indices with the last frame in x. See `mapsignals`.
"""
@Base.propagate_inbounds padlast(x,i,ixs...) = x[end,ixs...]
pad_stream(::typeof(padlast)) = true
pad_index_constant(::typeof(padlast)) = true

"""
    padcycle(x,ixs...)

Pad indices by wrapping around, starting back at the first sample.
This only works on objects with a known length: `AbstractArray`
and `SampleBuf` objects.
"""
@Base.propagate_inbounds padcycle(x,i,ixs...) = x[(i-1 % end)+1,ixs...]

# ASSUMPTION: sources have the same format and channel count (that is,
# promote_signals should first be called before passing input to a MappedSource
# constructor)
struct MappedSource{R,T,Fn,P,Ss,Fs,Bs} <: SampleSource{R,T}
    fn::Fn
    pad::P
    sources::Ss
    firstsample::Fs
    buffers::Bs
    buflen::Vector{Int}
end
firstsample_unused(x::MappedSource) = x.buflen[1] < 0
function MappedSource(fn::Fn,pad::P,sources,buffers::Bs) where {Fn,P,Bs}
    sr = usamplerate(sources[1])
    sources = tosource.(sources)
    Ss = Tuple{typeof.(sources)...}
    buflen = zeros(Int,length(buffers))

    # compute the first sample of the mapped source so we can figure out the
    # `eltype`.
    firstsample = read_first_sample(fn,pad,sources)
    if firstsample isa Type
        # `read_first_sample` returned a type: there are no samples available
        # and all buffers were padded. Just mark the appropriate types
        # and return a `MappedSource` that will provide 0 samples.
        Fs = firstsample
        T = eltype(firstsample)
    else
        # at least one sample is available: mark the types and create a mapped
        # source that will provide the samples, indicating with a -1 that the
        # first sample has been read, and has yet to be 'used' by the mapped
        # source
        Fs = typeof(firstsample)
        T = eltype(firstsample)
        buflen[1] = -1 ## hack to mark that firstsample is unused
    end

    # create the mapped source
    MappedSource{sr,T,Fn,P,Ss,Fs,Bs}(fn, pad, sources, firstsample, buffers,
                                     buflen)
end

function read_first_sample(fn,pad,sources::Tuple)
    bufs = map(sources) do source
        Array{eltype(source)}(undef,1,nchannels(source))
    end
    maxn = 0
    for (source,buf) in zip(sources,bufs)
        n = read!(source,buf,IsSignal{usamplerate(source),eltype(buf)}())
        maxn = max(n,maxn)
        if n < 1
            if pad_empty_array(pad)
                buf[1,:] = apply_pad(pad,buf,1,:)
            else
                error("One of the signals ($source) has no samples but the ",
                      "padding function $pad requires at least one sample ",
                      "to exist.")
            end
        end
    end
    result = fn.(map(buf -> buf[1,:],bufs)...)
    (maxn > 0) ? result : typeof(result)
end

MappedSource(f,xs...;pad=padding(f),blocksize) =
    MappedSource(f,pad,xs,select_buffer.(xs,blocksize))

select_buffer(x::SampleSource,blocksize) =
    Array{eltype(x)}(undef, blocksize, nchannels(x))
select_buffer(x::SampleBuf,blocksize) = nothing
select_buffer(x::SingletonSource,blocksize) = nothing

nchannels(x::MappedSource) = nchannels(x.sources[1])
function Base.read!(source::MappedSource{R}, result::AbstractArray,
                    ::IsSignal{R}) where R
    offset = 0
    length_result = nframes(result)
    if firstsample_unused(source)
        result[1,:] = source.firstsample
        offset += 1
        length_result -= 1
    end

    padded = map((s,b,l) -> padbuffer(s,b,l,length_result,source.pad),
                 source.sources, source.buffers, source.buflen)
    # @show padded[1]
    # @show padded[2]

    source.buflen .= map(nframes ∘ first,padded)
    start = 1
    for (i,len) in enumerate(sort(source.buflen))
        len = max(len,length_result)
        selected = map(padded) do (buf,padding)
            nframes(buf) >= len ?
                view(buf,start:len,:) :
                view(padding,start:len,:)
        end
        result[(start:len) .+ offset,:] .= source.fn.(selected...)
        start = len+1
    end
    start-1 + offset
end

function padbuffer(source::SampleSource,buffer,buflen,framecount,pad)
    n = read!(source, view(buffer,1:framecount))
    if n > 0
        if n < framecount && !pad_stream(pad)
            error("$pad does not support stream padding.")
        end

        buffer, PaddedArray(view(buffer,1:n),framecount,pad,0)
    else
        if !pad_stream(pad)
            error("$pad does not support stream padding.")
        end

        [], PaddedArray(view(buffer,1:buflen),framecount,pad,buflen)
    end
end

function padbuffer(source::ArrayLikeSource,buffer,buflen,framecount,pad)
    if source.read < nframes(source.buf)
        start = source.read+1
        stop = min(source.read+framecount,nframes(source.buf))
        source.read = stop
        view(source.buf,start:stop,:),
          PaddedArray(source.buf, framecount, pad, stop)
    else
        [], PaddedArray(source.buf, framecount, pad, source.read)
    end
end

struct PaddedArray{P,A,T,N} <: AbstractArray{T,N}
    pad::P
    data::A
    length::Int
    offset::Int
end
function PaddedArray(data::A,length,pad::P,offset) where {A,P}
    if pad_index_constant(pad)
        val = pad(data,1)
        PaddedArray{typeof(val),A,eltype(A),ndims(A)}(val,data,length,offset)
    else
        PaddedArray{P,A,eltype(A),ndims(A)}(pad,data,length,offset)
    end
end
Base.size(x::PaddedArray) = (x.length,Base.tail(size(x.data))...)
@Base.propagate_inbounds Base.getindex(x::PaddedArray,i::Int...) =
    x.pad(x.data,i[1]+x.offset,Base.tail(i)...)
@Base.propagate_inbounds Base.getindex(x::PaddedArray{<:Number},i::Int...) =
    eltype(x)(x.pad)

function padbuffer(source::SingletonSource,buffer,buflen,framecount,pad)
    SingletonBuffer(source.num,framecount), []
end
struct SingletonBuffer{T} <: AbstractArray{T,1}
    val::T
    len::Int
end
Base.size(x::SingletonBuffer) = (x.len,)
Base.IndexStyle(::Type{<:SingletonBuffer}) = IndexLinear()
@Base.propagate_inbounds Base.getindex(x::SingletonBuffer,i::Int...) = x.val

"""
    mix(xs...;pad=padzero)

Mix (sum) signals, or anything that can be interpreted as a signal (arrays and
numbers) together, padding the shorter signals with zeros.  Coerces the sample
rate and number of channels of all signals to be the same.

Custom padding can be used, refer to the documentation for `mapsignals` for
details.
"""
mix(xs...;kwds...) = mapsignals(+,xs...;kwds...)
mix!(result,xs...;kwds...) = mapsignals!(+,result,xs...;kwds...)

"""
    amplify(xs...;pad=padlast)

Amplify (multiply) signals, or anything that can be interpreted as a signla
(arrays and numbers) together, padding the shorter signals with their last
sample. Coerces the samplerate and channels of all signals to be the same.

Custom padding can be used, refer to the documentation for `mapsignals` for
details.
"""
amplify(xs...;kwds...) = mapsignals(*,xs...;kwds...)
amplify!(result,xs...;kwds...) = mapsignals!(*,result,xs...;kwds...)

# """
#     channnels(xs...;pad=padzero)

# Creates a multi-channel signal from multiple single channel signals,
# padding signals that are too short (by default) with zeros.

# Custom padding can be used, refer to the documentation for `mapsignals` for
# details.
# """
# TODO: cannot exactly use mapsignals, because it can't handle changes in
# dimensionality
