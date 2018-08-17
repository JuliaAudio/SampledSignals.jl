export SampleFreqBuf, SampleTimeBuf

"""
Wraps any Abstract array as a signal of regularly-sampled values.
The arrays must be 1D or 2D. The rows correspond to time points and the
columns to channels.
"""
struct SampleBuf{A, R, T, N} <: AbstractArray{T, N}
    data::A
    function SampleBuf{A,R,T,N}(data::A) where {A,R,T,N}
        @assert N ∈ [1,2] "Signal dimension must be 1 or 2."
        @assert R isa Quantity "Unspecified units of sample rate."
        new{A,R,T,N}(data)
    end
end

function SampleBuf(arr::AbstractArray{T, N}, R::Number) where {T,N}
    SampleBuf{typeof(arr), format(R), T, N}(arr)
end
SampleBuf(arr::AbstractArray, sr::Real, dim::Symbol) =
    SampleBuf(arr,sr/dimsymbol(dim))
function dimsymbol(dim::Symbol)
    dim == :time ? s :
    dim == :freq ? Hz :
    error("Unexpected dimension specification $dim.")
end
signal(x::AbstractArray,R,::NotSignal) = SampleBuf(x,R)

Base.Array(x::SampleBuf) = x.data
SampleBufVector{A,R,T} = SampleBuf{A,R,T,1}
SampleBufMatrix{A,R,T} = SampleBuf{A,R,T,2}
SignalFormat(x::SampleBuf{<:Any,R,T}) where {R,T} = IsSignal{R,T}()
Base.copy(x::SampleBuf{<:Any,R}) where R = SampleBuf(copy(x.data),R)

ismono(x::SampleBufVector) = true
isstereo(x::SampleBufVector) = false

dims_to_frames(::Type{T},len,ch,rate) where T<:Integer = (inframes(T,len,rate),ch)
dims_to_frames(::Type{T},len,rate) where T<:Integer = (inframes(T,len,rate),)
SampleBuf(::Type{T},sr::Real,dims...) where T<:Number =
    SampleBuf(T,sr*Hz,dims...)
SampleBuf(::Type{T},sr::Real,dim::Symbol,dims...) where T<:Number =
    SampleBuf(T,sr*dimsymbol(dim),dims...)
function SampleBuf(::Type{T},sr::Quantity,dims...) where T<:Number
    dims = dims_to_frames(Int,dims...,sr)
    SampleBuf(Array{T}(undef,dims...),sr)
end

"""
    signal(fn,freq,length;phase=0,ϕ=phase,samplerate=48000)

Generate a mono signal of the given length by passing function `fn` a `Float64`
phase value for each sample. The phase (in radians) starts at `ϕ` and
progresses at the given frequency but it does not wrap around (`mod2pi` can be
used if needed). Without a unit the sample rate and freq are assumed to be in
`Hz` and if they do have a unit, they must have the same dimension.

As an example, the following creates a 1 second pure tone at 1 kHz.

    signal(sin,1kHz,1s)
"""
function signal(fn::Function,freq,length;phase=0,ϕ=phase,samplerate=48kHz)
    sr = inunits(samplerate)
    len = inframes(Int,length,sr*Hz)
    phases = ϕ .+ 1:len.*(2π * ustrip(uconvert(Unitful.NoUnits,
                                               inunits(freq) / sr)))

    SampleBuf(br.(fn.(phases)),samplerate)
end
inunits(x::Quantity) = x
inunits(x) = inHz(x)

# `AbstractArray` objects can be interpreted as signals using `SampleBuf`
signal(x::AbstractArray,::Type{R},::NotSignal) where R<:Quantity =
    SampleBuf(x,R)

# terminology:
# sample - a single value representing the amplitude of 1 channel at some point in time (or frequency)
# channel - a set of samples running in parallel
# frame - a collection of samples from each channel that were sampled simultaneously

# audio methods
nchannels(buf::AbstractArray{T, 2}) where {T} = size(buf, 2)
nchannels(buf::AbstractArray{T, 1}) where {T} = 1
nframes(buf::AbstractArray) = size(buf, 1)

domain(buf::SampleBuf) =
    range(0.0, stop=(nframes(buf)-1)/samplerate(buf), length=nframes(buf))

# There's got to be a better way to define these functions, but the dispatch
# and broadcast behavior for AbstractArrays is complex and has subtle differences
# between Julia versions, so we basically just override functions here as they
# come up as problems

import Base: +,-,*,/
for op in (:+,:-,:*,:/)
    @eval $op(xs::SampleBuf...) = mapsignals($op,xs...)
    @eval $op(x::Number,y::SampleBuf) = mapsignals($op,x,y)
    @eval $op(x::AbstractArray,y::SampleBuf) = mapsignals($op,x,y)
    @eval $op(x::SampleBuf,y::Number) = mapsignals($op,x,y)
    @eval $op(x::SampleBuf,y::AbstractArray) = mapsignals($op,x,y)

    # to resolve method ambiguity
    @eval $op(xs::SampleBufVector...) = mapsignals($op,xs...)
    @eval $op(x::SampleBufVector,y::AbstractVector) = mapsignals($op,x,y)
    @eval $op(y::AbstractVector,x::SampleBufVector) = mapsignals($op,x,y)
end

# Broadcasting in Julia 0.7
# `find_buf` has borrowed from https://docs.julialang.org/en/latest/manual/interfaces/#Selecting-an-appropriate-output-array-1

import Base.broadcast
if VERSION >= v"0.7.0-DEV-4936" # Julia PR 26891

    struct SampleBufStyle{R,N} <: Broadcast.AbstractArrayStyle{N} end
    const SampleBufBroadcasted{R,N} = Broadcast.Broadcasted{SampleBufStyle{R,N}}
    SampleBufStyle{R,_}(::Val{N}) where {R,N,_} = SampleBufStyle{R,N}()

    Base.BroadcastStyle(::Type{T}) where {R,T <: SampleBuf{<:Any,R}} =
        SampleBufStyle{R,ndims(T)}()
    function Base.BroadcastStyle(x::SampleBufStyle{R1,N1},
                                 y::SampleBufStyle{R2,N2}) where {R1,R2,N1,N2}
        if R1 != R2
            error("Sample rate of buffers must match. To operate over mixed"*
                  " sample rate buffers, use non-broadcasting arithematic, `mix`"*
                  " `amplify` or `mapsignals`.")
        end

        SampleBufStyle{R1,max(N1,N1)}()
    end
    function Base.similar(bc::SampleBufBroadcasted{R},::Type{T}) where {R,T}
        SampleBuf(similar(Array{T},axes(bc)),R)
    end
else
    # define broadcasting application
    function broadcast(op, A1::SampleBuf, A2::SampleBuf)
        if !isapprox(samplerate(A1), samplerate(A2))
            error("samplerate-converting arithmetic not supported yet")
        end
        SampleBuf(broadcast(op, A1.data, A2.data), usamplerate(A1))
    end
    function broadcast(op, A1::SampleBuf, A2::Union{AbstractArray,Number})
        SampleBuf(broadcast(op, A1.data, A2), usamplerate(A1))
    end
    function broadcast(op, A1::Union{AbstractArray,Number}, A2::SampleBuf)
        SampleBuf(broadcast(op, A1, A2.data), usamplerate(A2))
    end
    function broadcast(op, A1::SampleBuf)
        SampleBuf(broadcast(op, A1.data), usamplerate(A1))
    end

end # if VERSION

# make Hz more readable, print all other units based on the preferred
# format (Hz cannot be set to preferred becuase it is derived from time).

# from @mbauman's Sparklines.jl package
const ticks = ['▁','▂','▃','▄','▅','▆','▇','█']
# 3-arg version (with explicit mimetype) is needed because we subtype AbstractArray,
# and there's a 3-arg version defined in show.jl
function show(io::IO, ::MIME"text/plain", buf::SampleBuf)
    println(io, "$(nframes(buf))-frame, $(nchannels(buf))-channel, "*
            string(eltype(buf))*
            " buffer.")
    len = upreferred(nframes(buf) / usamplerate(buf))
    print(io, show_samplerate(len)*" sampled at "*
          show_samplerate(usamplerate(buf)))
    nframes(buf) > 0 && showchannels(io, buf)
end

function showchannels(io::IO, buf::SampleBuf, widthchars=80)
    # number of samples per block
    blockwidth = round(Int, nframes(buf)/widthchars, RoundUp)
    nblocks = round(Int, nframes(buf)/blockwidth, RoundUp)
    blocks = Array{Char}(undef, nblocks, nchannels(buf))
    for blk in 1:nblocks
        i = (blk-1)*blockwidth + 1
        n = min(blockwidth, nframes(buf)-i+1)
        peaks = Compat.maximum(abs.(float.(buf[(1:n) .+ i .- 1, :])), dims=1)
        if !any(isnan,peaks)
          # clamp to -60dB, 0dB
          peaks = clamp.(20 .* log10.(peaks), -60.0, 0.0)
          idxs = trunc.(Int, (peaks.+60)./60 .* (length(ticks)-1)) .+ 1
          blocks[blk, :] = ticks[idxs]
        else
          blocks[blk, :] = ticks[1]
        end
    end
    for ch in 1:nchannels(buf)
        println(io)
        print(io, String(blocks[:, ch]))
    end
end

"""Get a pointer to the underlying data for the buffer. Will return a Ptr{T},
where T is the element type of the buffer. This is particularly useful for
passing to C libraries to fill the buffer"""
channelptr(buf::Array, channel, frameoffset=0) =
    pointer(buf) + ((channel-1)*nframes(buf)+frameoffset) * sizeof(eltype(buf))
channelptr(buf::SampleBuf{<:Array}, channel, frameoffset=0) =
    channelptr(buf.data, channel, frameoffset)
channelptr(buf::SampleBuf, ch, offset) =
    error("`SampleBuf` must have data of type `Array`.")


"""
    toindex(buf::SampleBuf, I)

Convert the given index value to one that Base knows how to use natively for
indexing
"""
function toindex end

toindex(buf::SampleBuf, t::FrameQuant) = inframes(Int, t) + 1
toindex(buf::SampleBuf, t::Number) = t
toindex(buf::SampleBuf, t::Quantity) = inframes(Int, t, usamplerate(buf)) + 1

# indexing by vectors of Quantities not yet supported
toindex(buf::SampleBuf, I::ClosedInterval{Int}) =
    toindex(buf, minimum(I)*frames):toindex(buf, maximum(I)*frames)
toindex(buf::SampleBuf, I::ClosedInterval{T}) where {T <: Quantity} =
    toindex(buf, minimum(I)):toindex(buf, maximum(I))

# AbstractArray interface methods
Base.size(buf::SampleBuf) = size(buf.data)
Base.IndexStyle(::Type{<:SampleBuf{A}}) where A = Base.IndexStyle(A)
Base.similar(buf::SampleBuf, ::Type{T}, dims::Dims) where {T} =
    SampleBuf(Array{T}(undef, dims), usamplerate(buf))
@Base.propagate_inbounds Base.getindex(buf::SampleBuf, i::Int...) =
    buf.data[i...]
@Base.propagate_inbounds Base.setindex!(buf::SampleBuf, v, i::Int...) =
    buf.data[i...] = v

# the index types that Base knows how to handle. Separate out those that index
# multiple results
const BuiltinMultiIdx = Union{Colon,AbstractArray{Int}}
const BuiltinIdx = Union{Int, BuiltinMultiIdx}
# the index types that will need conversion to built-in index types. Each of
# these needs a `toindex` method defined for it
const ConvertIdx{T1 <: Quantity, T2 <: Int} =
   Union{T1,ClosedInterval{T2},ClosedInterval{T1}}
         # Vector{T1}, # not supporting vectors of Quantities (yet?)
         # Range{T1}, # not supporting ranges (yet?)

Base.getindex(buf::SampleBuf, I::ConvertIdx) = buf[toindex(buf, I)]
Base.getindex(buf::SampleBuf, I1::ConvertIdx, I2::BuiltinIdx) =
    buf[toindex(buf, I1), I2]
# In Julia 0.5 scalar indices are now dropped, so by default indexing
# buf[5, 1:2] gives you a 2-frame single-channel buffer instead of a 1-frame
# two-channel buffer. The following getindex method bypasses this index dropping
Base.getindex(buf::SampleBuf, I1::Int, I2::BuiltinMultiIdx) = buf[I1:I1, I2]

function Base.vcat(xs::SampleBuf...)
    promoted = promote_signals(xs...)
    SampleBuf(vcat((p.data for p in promoted)...),usamplerate(promoted[1]))
end

struct Changedeltype{T,N,S} <: AbstractArray{T,N}
  data::S
end
Changedeltype(::Type{T},data::AbstractArray) where T =
    Changedeltype{T,ndims(data),typeof(data)}(data)
IndexStyle(::Type{<:Changedeltype{<:Any,<:Any,S}}) where S = IndexStyle(S)
Base.size(x::Changedeltype) = size(x.data)
@Base.propagate_inbounds function Base.getindex(p::Changedeltype{T},
                                                        ixs::Int...) where T
    T.(p.data[ixs...])
end
@Base.propagate_inbounds function Base.setindex(p::Changedeltype{T},v,
                                                        ixs::Int...) where T
    p.data[ixs...] = v
end
Base.copy(x::Changedeltype) = collect(x)

function tosamplerate(x::SampleBuf,R2,::IsSignal{R1}) where R1
    if dimension(R1) != dimension(R2)
        if dimension(R1) isa Unitful.Time &&
            dimension(R2) isa Unitful.Frequency
            toformat(ifft(x),R2)
        elseif dimension(R1) isa Unitful.Frequency &&
            dimension(R2) isa Unitful.Time
            toformat(fft(x),R2)
        else
            error("Do not know how to convert from sample rate of ",
                  "$(R1) to a samplerate of $R2.")
        end
    elseif !isapprox(R1,R2)
        if R1 > R2
            Base.warn("The sample rate of a signal was reduced; "*
                      "information past $(R2/2) will be lost.",bt=backtrace())
        end

        factor = uconvert(Unitful.NoUnits,R2/R1)
        SampleBuf(DSP.resample(x,factor),R2)
    else
        x
    end
end

struct SqueezedChannels{S,T} <: AbstractArray{T,1}
    data::S
end
SqueezedChannels(x) = SqueezedChannels{typeof(x),eltype(x)}(x)
IndexStyle(::Type{<:SqueezedChannels{S}}) where S = IndexStyle(S)
Base.size(x::SqueezedChannels) = (size(x.data,1),)
@Base.propagate_inbounds Base.getindex(p::SqueezedChannels,ixs::Int...) =
    sum(p.data[ixs[1],:])
Base.copy(x::SqueezedChannels) = collect(x)

struct SpreadChannels{S,T} <: AbstractArray{T,2}
    data::S
    ch::Int
end
SpreadChannels(x,ch) = SpreadChannels{typeof(x),eltype(x)}(x,ch)
IndexStyle(::Type{SpreadChannels{S}}) where S = IndexStyle(S)
Base.size(x::SpreadChannels) = (size(x.data,1),x.ch)
@Base.propagate_inbounds Base.getindex(p::SpreadChannels,ixs::Int...) =
    p.data[ixs[1]]
Base.copy(x::SpreadChannels) = collect(x)

function tochannels(x::SampleBuf,ch::Int)
  if nchannels(x) == ch
      x
  elseif nchannels(x) == 1
      SampleBuf(SpreadChannels(x,ch),format(x))
  elseif ch == 1
      SampleBuf(SqueezedChannels(x),format(x))
  else
      error("Don't know how to coerce a $(nchannels(x))-channel buffer",
           " to have $ch channels.")
  end
end

# equality
Base.:(==)(buf1::SampleBuf, buf2::SampleBuf) =
    usamplerate(buf1) == usamplerate(buf2) &&
    all(buf1.data .== buf2.data)

function FFTW.fft(buf::SampleBuf{<:Any,R}) where R
    if R isa Unitful.Frequency
        SampleBuf(FFTW.fft(buf.data), nframes(buf)/usamplerate(buf))
    elseif R isa Unitful.Time
        error("Expected temporal buffer, got frequency buffer. Call ifft",
              " instead.")
    else
        error("Unsupported samplerate dimension of $(dimension(R)).")
    end
end
function FFTW.ifft(buf::SampleBuf{<:Any,R}) where R
    if R isa Unitful.Frequency
        error("Expected frequency buffer, got temporal buffer. Call ifft",
              " instead.")
    elseif R isa Unitful.Time
        SampleBuf(FFTW.ifft(buf.data), nframes(buf)/usamplerate(buf))
    else
        error("Unsupported samplerate dimension of $(dimension(R)).")
    end
end

DSP.conv(b1::SampleBuf, b2::SampleBuf) =
    conv_helper(promote_signals(b1,b2)...)
DSP.conv(b1::SampleBuf, b2::AbstractArray) =
    conv_helper(promote_signals(b1,b2)...)
DSP.conv(b1::AbstractArray, b2::SampleBuf) =
    conv_helper(promote_signals(b1,b2)...)
function conv_helper(b1,b2)
    out = SampleBuf(eltype(b1),usamplerate(b1),nframes(b1)+nframes(b2)-1,
                    Base.tail(size(b1))...)
    for ch in 1:nchannels(b1)
        out[:, ch] = conv(b1.data[:, ch], b2.data[:, ch])
    end

    out
end


