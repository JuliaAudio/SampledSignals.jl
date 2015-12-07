"""
Represents a multi-channel sample buffer. The wrapped data is a MxN array with M
samples and N channels. Signals in the time domain are represented by the
concrete type TimeSampleBuf and frequency-domain signals are represented by
FrequencySampleBuf. So a 1-second stereo audio buffer sampled at 44100Hz with
32-bit floating-point samples in the time domain would have the type
TimeSampleBuf{2, 44100, Float32}.
"""
abstract SampleBuf{N, SR, T <: Number} <: AbstractArray{T, 2}

# terminology:
# sample - a single value representing the amplitude of 1 channel at some point in time (or frequency)
# channel - a set of samples running in parallel
# frame - a collection of samples from each channel that were sampled simultaneously

# audio methods
samplerate{N, SR, T}(::SampleBuf{N, SR, T}) = SR
nchannels{N, SR, T}(::SampleBuf{N, SR, T}) = N
nframes(buf::SampleBuf) = size(buf.data, 1)

# the index types that Base knows how to handle. Separate out those that index
# multiple results
typealias BuiltinMultiIdx Union{Colon,
                           Vector{Int},
                           Vector{Bool},
                           Range{Int}}
typealias BuiltinIdx Union{Int, BuiltinMultiIdx}
# the index types that will need conversion to built-in index types. Each of
# these needs a `toindex` method defined for it
typealias ConvertIdx{T1 <: SIUnits.SIQuantity, T2 <: Int} Union{T1,
                                                           # Vector{T1}, # not supporting vectors of SIQuantities (yet?)
                                                           # Range{T1}, # not supporting ranges (yet?)
                                                           Interval{T2},
                                                           Interval{T1}}

"""
    toindex(buf::SampleBuf, I)

Convert the given index value to one that Base knows how to use natively for
indexing
"""
function toindex end

# individual SIQuantities conversions should be defined by SampleBuf subtypes
toindex(buf::SampleBuf, i::SIUnits.SIQuantity) = throw(ArgumentError("$(typeof(i)) indexing not defined for $(typeof(buf))"))
# indexing by vectors of SIQuantities not yet supported
# toindex{T <: SIUnits.SIQuantity}(buf::SampleBuf, I::Vector{T}) = Int[toindex(buf, i) for i in I]
toindex(buf::SampleBuf, I::Interval{Int}) = I.lo:I.hi
toindex{T <: SIUnits.SIQuantity}(buf::SampleBuf, I::Interval{T}) = toindex(buf, I.lo):toindex(buf, I.hi)

# AbstractArray interface methods
Base.size(buf::SampleBuf) = size(buf.data)
Base.linearindexing{T <: SampleBuf}(::Type{T}) = Base.LinearFast()
# this is the fundamental indexing operation needed for the AbstractArray interface
Base.getindex(buf::SampleBuf, i::Int) = buf.data[i];
# need to implement the AbstractVector{Bool} method because the default implementation
# doesn't use checkindex so it throws
Base.getindex(buf::SampleBuf, I::AbstractVector{Bool}) = buf[find(I)]
# now we implement the methods that need to convert indices. luckily we only
# need to support up to 2D
Base.getindex(buf::SampleBuf, I::ConvertIdx) = buf[toindex(buf, I)]
Base.getindex(buf::SampleBuf, I1::ConvertIdx, I2::BuiltinIdx) = buf[toindex(buf, I1), I2]
Base.getindex(buf::SampleBuf, I1::BuiltinIdx, I2::ConvertIdx) = buf[I1, toindex(buf, I2)]
Base.getindex(buf::SampleBuf, I1::ConvertIdx, I2::ConvertIdx) = buf[toindex(buf, I1), toindex(buf, I2)]

# In Julia 0.5 scalar indices are now dropped, so by default indexing buf[5,
# 1:2] gives you a 2-frame single-channel buffer instead of a 1-frame
# two-channel buffer. The following getindex method defeats the index dropping
Base.getindex(buf::SampleBuf, I1::Int, I2::BuiltinMultiIdx) = buf[I1:I1, I2]

# we have to implement checksize because we always create a 2D buffer even when
# indexed with a linear range (returning a 1-channel buffer). Defining for the
# Bool case is just to resolve dispatch ambiguity
function Base.checksize{SR, T, N}(A::SampleBuf{1, SR, T}, I::AbstractArray{Bool, N})
    if length(A) != sum(I)
        throw(DimensionMismatch("index 1 selects $(sum(I)) elements, but length(A) = $(length(A))"))
    end
    nothing
end
function Base.checksize{SR, T}(A::SampleBuf{1, SR, T}, I::AbstractArray)
    if length(A) != length(I)
        throw(DimensionMismatch("index 1 has size $(size(I)), but size(A) = $(size(A))"))
    end
    nothing
end

function Base.setindex!(buf::SampleBuf, val, i::Int)
    buf.data[i] = val
end

# equality
import Base.==
==(buf1::SampleBuf, buf2::SampleBuf) =
    typeof(buf1) == typeof(buf2) &&
    samplerate(buf1) == samplerate(buf2) &&
    buf1.data == buf2.data

# Concrete SampleBuf types

# it's important to define Base.similar so that range-indexing returns the
# right type, instead of just a bare array

# TODO: maybe the unit should just be a type parameter and we can combine these

"A time-domain signal. See `SampleBuf` for details"
immutable TimeSampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

TimeSampleBuf{T}(arr::AbstractArray{T, 2}, SR::Real) = TimeSampleBuf{size(arr, 2), SR, T}(arr)
TimeSampleBuf{T}(arr::AbstractArray{T, 1}, SR::Real) = TimeSampleBuf{1, SR, T}(reshape(arr, (length(arr), 1)))
Base.similar{T}(buf::TimeSampleBuf, ::Type{T}, dims::Dims) = TimeSampleBuf(Array(T, dims), samplerate(buf))
toindex(buf::TimeSampleBuf, t::RealTime) = round(Int, t.val*samplerate(buf)) + 1
# TODO: we shouldn't need the `collect` once SIUnits supports LinSpace
domain(buf::TimeSampleBuf) = collect(0:(nframes(buf)-1)) / samplerate(buf) * s


"A frequency-domain signal. See `SampleBuf` for details"
immutable FrequencySampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

FrequencySampleBuf{T}(arr::AbstractArray{T, 2}, SR::Real) = FrequencySampleBuf{size(arr, 2), SR, T}(arr)
FrequencySampleBuf{T}(arr::AbstractArray{T, 1}, SR::Real) = FrequencySampleBuf{1, SR, T}(reshape(arr, (length(arr), 1)))
Base.similar{T}(buf::FrequencySampleBuf, ::Type{T}, dims::Dims) = FrequencySampleBuf(Array(T, dims), samplerate(buf))
# convert a frequency in Hz to an index. This assumes the buffer represents
# a spectrum (i.e. the result of an FFT) with the first bin representing 0Hz
toindex(buf::FrequencySampleBuf, f::RealFrequency) = round(Int, f.val * samplerate(buf)) + 1
domain(buf::FrequencySampleBuf) = collect(0:(nframes(buf)-1)) / samplerate(buf) * Hz

Base.fft(buf::TimeSampleBuf) = FrequencySampleBuf(fft(buf.data), nframes(buf)//samplerate(buf))
Base.ifft(buf::FrequencySampleBuf) = TimeSampleBuf(ifft(buf.data), nframes(buf)//samplerate(buf))
