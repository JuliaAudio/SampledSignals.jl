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

# function TimeSampleBuf{SR}(arr::Array{T, 2})
#     channels = size(arr, 2)
#     TimeSampleBuf{channels, SR, T}(arr)
# end

"A frequency-domain signal. See SampleBuf for details"
type FrequencySampleBuf{N, SR, T} <: SampleBuf{N, SR, T}
    data::Array{T, 2}
end

Base.size(buf::SampleBuf) = size(buf.data)
Base.linearindexing(T::Type{SampleBuf}) = Base.LinearFast()
Base.getindex(buf::SampleBuf, i::Int) = buf.data[i];
function Base.setindex!{N, SR, T}(buf::SampleBuf{N, SR, T}, val::T, i::Int)
    buf.data[i] = val
end
