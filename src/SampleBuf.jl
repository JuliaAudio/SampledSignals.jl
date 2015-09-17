"""
Represents a multi-channel sample buffer. The wrapped data is a MxN array with M
samples and N channels. Signals in the time domain are represented by the
concrete type TimeSampleBuf and frequency-domain signals are represented by
FrequencySampleBuf. So a 1-second stereo audio buffer sampled at 44100Hz with
32-bit floating-point samples in the time domain would have the type
TimeSampleBuf{2, 44100.0, Float32}.
"""
abstract SampleBuf{N, SR, T <: Number} <: AbstractArray{T, 2}

"A time-domain signal. See SampleBuf for details"
type TimeSampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

TimeSampleBuf{T}(arr::AbstractArray{T, 2}, SR::Real) = TimeSampleBuf{size(arr, 2), SR, T}(arr)
TimeSampleBuf{T}(arr::AbstractArray{T, 1}, SR::Real) = TimeSampleBuf{1, SR, T}(reshape(arr, (length(arr), 1)))

# function TimeSampleBuf{SR}(arr::Array{T, 2})
#     channels = size(arr, 2)
#     TimeSampleBuf{channels, SR, T}(arr)
# end

"A frequency-domain signal. See SampleBuf for details"
type FrequencySampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

FrequencySampleBuf{T}(arr::AbstractArray{T, 2}, SR::Real) = FrequencySampleBuf{size(arr, 2), SR, T}(arr)
FrequencySampleBuf{T}(arr::AbstractArray{T, 1}, SR::Real) = FrequencySampleBuf{1, SR, T}(reshape(arr, (length(arr), 1)))

# audio methods
samplerate{N, SR, T}(buf::SampleBuf{N, SR, T}) = SR
nchannels{N, SR, T}(buf::SampleBuf{N, SR, T}) = N

# took some good ideas from @mbauman's AxisArrays package
typealias Idx Union(Colon,Int,Array{Int,1},Range{Int})
_idx(buf::TimeSampleBuf, t::RealTime) = round(Int, t.val*samplerate(buf))
# convert a frequency in Hz to an index, assuming the frequency buffer
# represents an N-point DFT of a signal sampled at SR Hz
_idx(buf::FrequencySampleBuf, f::RealFrequency) = round(Int, f.val * size(buf, 1) / samplerate(buf)) + 1

# AbstractArray interface methods
Base.size(buf::SampleBuf) = size(buf.data)
Base.linearindexing{T <: SampleBuf}(::Type{T}) = Base.LinearFast()
Base.getindex(buf::TimeSampleBuf, i::Int) = buf.data[i];
Base.getindex(buf::FrequencySampleBuf, i::Int) = buf.data[i];

# also define 2D indexing so it doesn't get caught by the I... case below
Base.getindex(buf::TimeSampleBuf, i::Int, j::Int) = buf.data[i, j];
Base.getindex(buf::FrequencySampleBuf, i::Int, j::Int) = buf.data[i, j];

# we define the range indexing here so that we can wrap the result in the
# appropriate SampleBuf type. Otherwise you just get a bare array out
Base.getindex(buf::TimeSampleBuf, I::Idx...) = TimeSampleBuf(buf.data[I...], samplerate(buf))
Base.getindex(buf::FrequencySampleBuf, I::Idx...) = FrequencySampleBuf(buf.data[I...], samplerate(buf))

# this should catch indexing with seconds
Base.getindex(buf::TimeSampleBuf, t::RealTime) = buf.data[_idx(buf, t)];
Base.getindex(buf::TimeSampleBuf, t::RealTime, ch::Integer) = buf.data[_idx(buf, t), ch]
Base.getindex(buf::FrequencySampleBuf, t::RealFrequency) = buf.data[_idx(buf, t)];
Base.getindex(buf::FrequencySampleBuf, t::RealFrequency, ch::Integer) = buf.data[_idx(buf, t), ch]
# Base.getindex(buf::TimeSampleBuf, I...) = TimeSampleBuf(buf.data[[_idx(buf, i) for i in I]...], samplerate(buf))
# Base.getindex(buf::TimeSampleBuf, I::Idx...) = TimeSampleBuf(buf.data[I...], samplerate(buf))
# Base.getindex(buf::FrequencySampleBuf, I...) = FrequencySampleBuf(buf.data[map(_idx, I)...], samplerate(buf))
# Base.getindex(buf::FrequencySampleBuf, I::Idx...) = FrequencySampleBuf(buf.data[I...], samplerate(buf))
function Base.setindex!(buf::SampleBuf, val, i::Int)
    buf.data[i] = val
end

# equality
import Base.==
==(buf1::SampleBuf, buf2::SampleBuf) = (samplerate(buf1) == samplerate(buf2) && buf1.data == buf2.data)
