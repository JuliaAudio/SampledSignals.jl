"""
Represents a multi-channel sample buffer. The wrapped data is a MxN array with M
samples and N channels. Signals in the time domain are represented by the
concrete type TimeSampleBuf and frequency-domain signals are represented by
FrequencySampleBuf. So a 1-second stereo audio buffer sampled at 44100Hz with
32-bit floating-point samples in the time domain would have the type
TimeSampleBuf{2, 44100.0, Float32}.
"""
abstract SampleBuf{N, SR, T <: Number} <: AbstractArray{T, 2}

# audio methods
samplerate{N, SR, T}(buf::SampleBuf{N, SR, T}) = SR
nchannels{N, SR, T}(buf::SampleBuf{N, SR, T}) = N

# took some good ideas from @mbauman's AxisArrays package
typealias Idx Union{Colon,Int,Array{Int,1},Range{Int}}

# AbstractArray interface methods
Base.size(buf::SampleBuf) = size(buf.data)
Base.linearindexing{T <: SampleBuf}(::Type{T}) = Base.LinearFast()
Base.getindex(buf::SampleBuf, i::Int) = buf.data[i];
# need to implement the AbstractVector{Bool} method because the default implementation
# doesn't use checkindex so it throws
Base.getindex(buf::SampleBuf, I::AbstractVector{Bool}) = buf[find(I)]
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

Base.getindex{T <: Integer}(buf::SampleBuf, I::Interval{T}) = buf[I.lo:I.hi]
Base.getindex{T <: Integer}(buf::SampleBuf, I::Interval{T}, ch::Integer) = buf[I.lo:I.hi, ch]
# individual subtypes implement unitidx to convert physical units into indices
Base.getindex(buf::SampleBuf, v::SIUnits.SIQuantity) = buf.data[unitidx(buf, v)]
Base.getindex(buf::SampleBuf, v::SIUnits.SIQuantity, ch::Integer) = buf.data[unitidx(buf, v), ch]
Base.getindex{T <: SIUnits.SIQuantity}(buf::SampleBuf, v::Interval{T}) = buf[unitidx(buf, v.lo)..unitidx(buf, v.hi)]

function Base.setindex!(buf::SampleBuf, val, i::Int)
    buf.data[i] = val
end

# equality
import Base.==
# TODO: make sure types of buf1 and buf2 are the same
==(buf1::SampleBuf, buf2::SampleBuf) = (samplerate(buf1) == samplerate(buf2) && buf1.data == buf2.data)


"A time-domain signal. See SampleBuf for details"
immutable TimeSampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

TimeSampleBuf{T}(arr::AbstractArray{T, 2}, SR::Real) = TimeSampleBuf{size(arr, 2), SR, T}(arr)
TimeSampleBuf{T}(arr::AbstractArray{T, 1}, SR::Real) = TimeSampleBuf{1, SR, T}(reshape(arr, (length(arr), 1)))
Base.similar{T}(buf::TimeSampleBuf, ::Type{T}, dims::Dims) = TimeSampleBuf(Array(T, dims), samplerate(buf))
unitidx(buf::TimeSampleBuf, t::RealTime) = round(Int, t.val*samplerate(buf))


"A frequency-domain signal. See SampleBuf for details"
immutable FrequencySampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

FrequencySampleBuf{T}(arr::AbstractArray{T, 2}, SR::Real) = FrequencySampleBuf{size(arr, 2), SR, T}(arr)
FrequencySampleBuf{T}(arr::AbstractArray{T, 1}, SR::Real) = FrequencySampleBuf{1, SR, T}(reshape(arr, (length(arr), 1)))
Base.similar{T}(buf::FrequencySampleBuf, ::Type{T}, dims::Dims) = FrequencySampleBuf(Array(T, dims), samplerate(buf))
# convert a frequency in Hz to an index, assuming the frequency buffer
# represents an N-point DFT of a signal sampled at SR Hz
unitidx(buf::FrequencySampleBuf, f::RealFrequency) = round(Int, f.val * size(buf, 1) / samplerate(buf)) + 1
