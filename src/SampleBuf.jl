abstract type AbstractSampleBuf{T, N} <: AbstractArray{T, N} end

"""
Represents a multi-channel regularly-sampled buffer that stores its own sample
rate (in samples/second). The wrapped data is an N-dimensional array. A 1-channel
sample can be represented with a 1D array or an Mx1 matrix, and a C-channel
buffer will be an MxC matrix. So a 1-second stereo audio buffer sampled at
44100Hz with 32-bit floating-point samples in the time domain would have the
type SampleBuf{Float32, 2}.
"""
mutable struct SampleBuf{T, N} <: AbstractSampleBuf{T, N}
    data::Array{T, N}
    samplerate::Float64
end

# define constructor so conversion is applied to `sr`
SampleBuf(arr::Array{T, N}, sr::Real) where {T, N} = SampleBuf{T, N}(arr, sr)

"""
Represents a multi-channel regularly-sampled buffer representing the frequency-
domain spectrum of a `SampleBuf`. The wrapped data is an N-dimensional array. A
1-channel sample can be represented with a 1D array or an Mx1 matrix, and a
C-channel buffer will be an MxC matrix. So a 1-second stereo audio buffer
sampled at 44100Hz with 32-bit floating-point samples in the time domain would
have the type SampleBuf{Float32, 2}.
"""
mutable struct SpectrumBuf{T, N} <: AbstractSampleBuf{T, N}
    data::Array{T, N}
    samplerate::Float64
end

# define constructor so conversion is applied to `sr`
SpectrumBuf(arr::Array{T, N}, sr::Real) where {T, N} = SpectrumBuf{T, N}(arr, sr)

SampleBuf(T::Type, sr, dims...) = SampleBuf(Array{T}(dims...), sr)
SpectrumBuf(T::Type, sr, dims...) = SpectrumBuf(Array{T}(dims...), sr)
SampleBuf(T::Type, sr, len::Quantity) = SampleBuf(T, sr, inframes(len,sr))
SampleBuf(T::Type, sr, len::Quantity, ch) =
    SampleBuf(T, sr, inframes(len,sr), ch)
SpectrumBuf(T::Type, sr, len::Quantity) =
    SpectrumBuf(T, sr, round(Int,inHz(len)*sr))
SpectrumBuf(T::Type, sr, len::Quantity, ch) =
    SpectrumBuf(T, sr, round(Int,inHz(len)*sr))

# terminology:
# sample - a single value representing the amplitude of 1 channel at some point in time (or frequency)
# channel - a set of samples running in parallel
# frame - a collection of samples from each channel that were sampled simultaneously

# audio methods
samplerate(buf::AbstractSampleBuf) = buf.samplerate
nchannels(buf::AbstractSampleBuf{T, 2}) where {T} = size(buf.data, 2)
nchannels(buf::AbstractSampleBuf{T, 1}) where {T} = 1
nframes(buf::AbstractSampleBuf) = size(buf.data, 1)

function samplerate!(buf::AbstractSampleBuf, sr)
    buf.samplerate = sr

    buf
end

# define audio methods on raw buffers as well
nframes(arr::AbstractArray) = size(arr, 1)
nchannels(arr::AbstractArray) = size(arr, 2)

# it's important to define Base.similar so that range-indexing returns the
# right type, instead of just a bare array
Base.similar(buf::SampleBuf, ::Type{T}, dims::Dims) where {T} = SampleBuf(Array{T}(dims), samplerate(buf))
Base.similar(buf::SpectrumBuf, ::Type{T}, dims::Dims) where {T} = SpectrumBuf(Array{T}(dims), samplerate(buf))
domain(buf::AbstractSampleBuf) = linspace(0.0, (nframes(buf)-1)/samplerate(buf), nframes(buf))

# There's got to be a better way to define these functions, but the dispatch
# and broadcast behavior for AbstractArrays is complex and has subtle differences
# between Julia versions, so we basically just override functions here as they
# come up as problems
import Base: +, -, *, /
import Base.broadcast

const ArrayIsh = Union{Array, SubArray, LinSpace, StepRangeLen}
for btype in (:SampleBuf, :SpectrumBuf)
    # define non-broadcasting arithmetic
    for op in (:+, :-)
        @eval function $op(A1::$btype, A2::$btype)
            if !isapprox(samplerate(A1), samplerate(A2))
                error("samplerate-converting arithmetic not supported yet")
            end
            $btype($op(A1.data, A2.data), samplerate(A1))
        end
        @eval function $op(A1::$btype, A2::ArrayIsh)
            $btype($op(A1.data, A2), samplerate(A1))
        end
        @eval function $op(A1::ArrayIsh, A2::$btype)
            $btype($op(A1, A2.data), samplerate(A2))
        end
    end

    # define broadcasting application
    @eval function broadcast(op, A1::$btype, A2::$btype)
        if !isapprox(samplerate(A1), samplerate(A2))
            error("samplerate-converting arithmetic not supported yet")
        end
        $btype(broadcast(op, A1.data, A2.data), samplerate(A1))
    end
    @eval function broadcast(op, A1::$btype, A2::ArrayIsh)
        $btype(broadcast(op, A1.data, A2), samplerate(A1))
    end
    @eval function broadcast(op, A1::ArrayIsh, A2::$btype)
        $btype(broadcast(op, A1, A2.data), samplerate(A2))
    end
    @eval function broadcast(op, a1::Number, A2::$btype)
        $btype(broadcast(op, a1, A2.data), samplerate(A2))
    end
    @eval function broadcast(op, A1::$btype, a2::Number)
        $btype(broadcast(op, A1.data, a2), samplerate(A1))
    end
    @eval function broadcast(op, A1::$btype)
        $btype(broadcast(op, A1.data), samplerate(A1))
    end


    # define non-broadcast scalar arithmetic
    for op in (:+, :-, :*, :/)
        @eval function $op(A1::$btype, a2::Number)
            $btype($op(A1.data, a2), samplerate(A1))
        end
        @eval function $op(a1::Number, A2::$btype)
            $btype($op(a1, A2.data), samplerate(A2))
        end
    end
end

typename(::SampleBuf{T, N}) where {T, N} = "SampleBuf{$T, $N}"
unitname(::SampleBuf) = "s"
srname(::SampleBuf) = "Hz"
typename(::SpectrumBuf{T, N}) where {T, N} = "SpectrumBuf{$T, $N}"
unitname(::SpectrumBuf) = "Hz"
srname(::SpectrumBuf) = "s"

# from @mbauman's Sparklines.jl package
const ticks = ['▁','▂','▃','▄','▅','▆','▇','█']
# 3-arg version (with explicit mimetype) is needed because we subtype AbstractArray,
# and there's a 3-arg version defined in show.jl
function show(io::IO, ::MIME"text/plain", buf::AbstractSampleBuf)
    println(io, "$(nframes(buf))-frame, $(nchannels(buf))-channel $(typename(buf))")
    len = nframes(buf) / samplerate(buf)
    ustring = unitname(buf)
    srstring = srname(buf)
    print(io, "$(len)$ustring sampled at $(samplerate(buf))$srstring")
    nframes(buf) > 0 && showchannels(io, buf)
end

function showchannels(io::IO, buf::AbstractSampleBuf, widthchars=80)
    # number of samples per block
    blockwidth = round(Int, nframes(buf)/widthchars, RoundUp)
    nblocks = round(Int, nframes(buf)/blockwidth, RoundUp)
    blocks = Array{Char}(nblocks, nchannels(buf))
    for blk in 1:nblocks
        i = (blk-1)*blockwidth + 1
        n = min(blockwidth, nframes(buf)-i+1)
        peaks = maximum(abs.(float(buf[(1:n)+i-1, :])), 1)
        # clamp to -60dB, 0dB
        peaks = clamp.(20log10.(peaks), -60.0, 0.0)
        idxs = trunc.(Int, (peaks+60)/60 * (length(ticks)-1)) + 1
        blocks[blk, :] = ticks[idxs]
    end
    for ch in 1:nchannels(buf)
        println(io)
        print(io, convert(String, blocks[:, ch]))
    end
end

"""Get a pointer to the underlying data for the buffer. Will return a Ptr{T},
where T is the element type of the buffer. This is particularly useful for
passing to C libraries to fill the buffer"""
channelptr(buf::Array, channel, frameoffset=0) =
    pointer(buf) + ((channel-1)*nframes(buf)+frameoffset) * sizeof(eltype(buf))
channelptr(buf::AbstractSampleBuf, channel, frameoffset=0) =
    channelptr(buf.data, channel, frameoffset)

"""Mix the channels of the source array into the channels of the dest array,
using coefficients from the `mix` matrix. To mix an M-channel buffer to a
N-channel buffer, `mix` should be MxN. `src` and `dest` should not share
memory."""
function mix!(dest::AbstractMatrix, src::AbstractMatrix, mix::AbstractArray)
    inchans = nchannels(src)
    outchans = nchannels(dest)
    size(mix) == (inchans, outchans) || error("Mix Matrix should be $(inchans)x$(outchans)")
    A_mul_B!(dest, src, mix)
end

function mix!(dest::AbstractVector, src::AbstractVector, mix::AbstractArray)
    mix!(reshape(dest, (length(dest), 1)), reshape(src, (length(src), 1)), mix)
    dest
end

function mix!(dest::AbstractVector, src::AbstractMatrix, mix::AbstractArray)
    mix!(reshape(dest, (length(dest), 1)), src, mix)
    dest
end

function mix!(dest::AbstractMatrix, src::AbstractVector, mix::AbstractArray)
    mix!(dest, reshape(src, (length(src), 1)), mix)
end

# necessary because A_mul_B! doesn't handle SampleBufs on 0.4
# explicitly define 1D and 2D so they're more specific and don't trigger ambiguity
# warnings on 0.4
for N1 in (1, 2), N2 in (1, 2)
    @eval function mix!{T}(dest::AbstractSampleBuf{T, $N1}, src::AbstractSampleBuf{T, $N2}, mix::AbstractArray)
        mix!(dest.data, src.data, mix)
        dest
    end
    @eval function mix!{T1, T2}(dest::AbstractSampleBuf{T1, $N1}, src::AbstractSampleBuf{T2, $N2}, mix::AbstractArray)
        mix!(dest.data, src.data, mix)
        dest
    end
end

# necessary because A_mul_B! doesn't handle SampleBufs on 0.4
for MT in (AbstractMatrix, AbstractVector), N in (1, 2)
    @eval function mix!{T}(dest::$MT, src::AbstractSampleBuf{T, $N}, mix::AbstractArray)
        mix!(dest, src.data, mix)
    end

    @eval function mix!{T}(dest::AbstractSampleBuf{T, $N}, src::$MT, mix::AbstractArray)
        mix!(dest.data, src, mix)
        dest
    end
end


"""Mix the channels of the source array into the channels of the dest array,
using coefficients from the `mix` matrix. To mix an M-channel buffer to a
N-channel buffer, `mix` should be MxN. `src` and `dest` should not share
memory."""
function mix(src::AbstractArray, mix::AbstractArray)
    dest = similar(src, (nframes(src), size(mix, 2)))
    mix!(dest, src, mix)
end

"""Mix the channels of the `src` array into the mono `dest` array."""
function mono!(dest::AbstractArray, src::AbstractArray)
    mix!(dest, src, ones(nchannels(src), 1) ./ nchannels(src))
end

"""Mix the channels of the `src` array into a mono array."""
function mono(src::AbstractArray)
    dest = similar(src, (nframes(src), 1))
    mono!(dest, src)
end


# the index types that Base knows how to handle. Separate out those that index
# multiple results
const BuiltinMultiIdx = Union{Colon,
                        Vector{Int},
                        Vector{Bool},
                        Range{Int}}
const BuiltinIdx = Union{Int, BuiltinMultiIdx}
# the index types that will need conversion to built-in index types. Each of
# these needs a `toindex` method defined for it
const ConvertIdx{T1 <: Quantity, T2 <: Int} = Union{T1,
                                                # Vector{T1}, # not supporting vectors of Quantities (yet?)
                                                # Range{T1}, # not supporting ranges (yet?)
                                                ClosedInterval{T2},
                                                ClosedInterval{T1}}

"""
    toindex(buf::SampleBuf, I)

Convert the given index value to one that Base knows how to use natively for
indexing
"""
function toindex end

toindex(buf::SampleBuf{T, N}, t::Number) where {T <: Number, N} = t
toindex(buf::SampleBuf{T, N}, t::Quantity) where {T <: Number, N} =
  inframes(t,samplerate(buf)) + 1
toindex(buf::SampleBuf{T, N}, t::FrameQuant) where {T <: Number, N} = ustrip(t)
toindex(buf::SpectrumBuf{T, N}, f::Quantity) where {T <: Number, N} =
    round(Int, inHz(f)*samplerate(buf)) + 1
toindex(buf::SpectrumBuf{T, N}, f::Number) where {T <: Number, N} = f
toindex(buf::SpectrumBuf{T, N}, f::FrameQuant) where {T <: Number, N} = ustrip(f)

# indexing by vectors of Quantities not yet supported
toindex(buf::AbstractSampleBuf, I::ClosedInterval{Int}) = minimum(I):maximum(I)
toindex(buf::AbstractSampleBuf, I::ClosedInterval{T}) where {T <: Quantity} =
    toindex(buf, minimum(I)):toindex(buf, maximum(I))

# AbstractArray interface methods
Base.size(buf::AbstractSampleBuf) = size(buf.data)
Base.IndexStyle(::Type{T}) where {T <: AbstractSampleBuf} = Base.IndexLinear()
# this is the fundamental indexing operation needed for the AbstractArray interface
Base.getindex(buf::AbstractSampleBuf, i::Int) = buf.data[i];

# now we implement the methods that need to convert indices. luckily we only
# need to support up to 2D
Base.getindex(buf::AbstractSampleBuf, I::ConvertIdx) = buf[toindex(buf, I)]
Base.getindex(buf::AbstractSampleBuf, I1::ConvertIdx, I2::BuiltinIdx) = buf[toindex(buf, I1), I2]
Base.getindex(buf::AbstractSampleBuf, I1::BuiltinIdx, I2::ConvertIdx) = buf[I1, toindex(buf, I2)]
Base.getindex(buf::AbstractSampleBuf, I1::ConvertIdx, I2::ConvertIdx) = buf[toindex(buf, I1), toindex(buf, I2)]
# In Julia 0.5 scalar indices are now dropped, so by default indexing
# buf[5, 1:2] gives you a 2-frame single-channel buffer instead of a 1-frame
# two-channel buffer. The following getindex method defeats the index dropping
Base.getindex(buf::AbstractSampleBuf, I1::Int, I2::BuiltinMultiIdx) = buf[I1:I1, I2]

function Base.setindex!(buf::AbstractSampleBuf, val, i::Int)
    buf.data[i] = val
end

# equality
import Base.==
==(buf1::AbstractSampleBuf, buf2::AbstractSampleBuf) =
    samplerate(buf1) == samplerate(buf2) &&
    buf1.data == buf2.data

Base.fft(buf::SampleBuf) = SpectrumBuf(fft(buf.data), nframes(buf)/samplerate(buf))
Base.ifft(buf::SpectrumBuf) = SampleBuf(ifft(buf.data), nframes(buf)/samplerate(buf))

# does a per-channel convolution on SampleBufs
for buftype in (:SampleBuf, :SpectrumBuf)
    @eval function Base.conv(b1::$buftype{T, 1}, b2::$buftype{T, 1}) where {T}
        if !isapprox(samplerate(b1), samplerate(b2))
            error("Resampling convolution not yet supported")
        end
        $buftype(conv(b1.data, b2.data), samplerate(b1))
    end

    @eval function Base.conv(b1::$buftype{T, N1}, b2::$buftype{T, N2}) where {T, N1, N2}
        if !isapprox(samplerate(b1), samplerate(b2))
            error("Resampling convolution not yet supported")
        end
        if nchannels(b1) != nchannels(b2)
            error("Broadcasting convolution not yet supported")
        end
        out = $buftype(T, samplerate(b1), nframes(b1)+nframes(b2)-1, nchannels(b1))
        for ch in 1:nchannels(b1)
            out[:, ch] = conv(b1.data[:, ch], b2.data[:, ch])
        end

        out
    end

    @eval function Base.conv(b1::$buftype{T, 1}, b2::StridedVector{T}) where {T}
        $buftype(conv(b1.data, b2), samplerate(b1))
    end

    @eval Base.conv(b1::StridedVector{T}, b2::$buftype{T, 1}) where {T} = conv(b2, b1)

    @eval function Base.conv(b1::$buftype{T, 2}, b2::StridedMatrix{T}) where {T}
        if nchannels(b1) != nchannels(b2)
            error("Broadcasting convolution not yet supported")
        end
        out = $buftype(T, samplerate(b1), nframes(b1)+nframes(b2)-1, nchannels(b1))
        for ch in 1:nchannels(b1)
            out[:, ch] = conv(b1.data[:, ch], b2[:, ch])
        end

        out
    end

    @eval Base.conv(b1::StridedMatrix{T}, b2::$buftype{T, 2}) where {T} = conv(b2, b1)
end
