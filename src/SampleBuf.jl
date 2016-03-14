"""
Represents a multi-channel regularly-sampled buffer that stores its own sample
rate. The wrapped data is an N-dimensional array. A 1-channel sample can be
represented with a 1D array or an Mx1 matrix, and a C-channel buffer will be an
MxC matrix. So a 1-second stereo audio buffer sampled at 44100Hz with
32-bit floating-point samples in the time domain would have the type
SampleBuf{Float32, 2}.
"""
immutable SampleBuf{T <: Number, N, U <: SIQuantity} <: AbstractArray{T, N}
    data::Array{T, N}
    samplerate::U
end

# handle creation with a unitful sample rate
SampleBuf(T, sr::SIQuantity, dims...) = SampleBuf(Array(T, dims...), sr)

# default to sampling rate in Hz if given rate is unitless
SampleBuf(T, sr::Real, dims...) = SampleBuf(Array(T, dims...), sr*Hz)
SampleBuf(arr::Array, sr::Real) = SampleBuf(arr, sr*Hz)

# terminology:
# sample - a single value representing the amplitude of 1 channel at some point in time (or frequency)
# channel - a set of samples running in parallel
# frame - a collection of samples from each channel that were sampled simultaneously

# audio methods
samplerate(buf::SampleBuf) = buf.samplerate
nchannels{T, U}(buf::SampleBuf{T, 2, U}) = size(buf.data, 2)
nchannels{T, U}(buf::SampleBuf{T, 1, U}) = 1
nframes(buf::SampleBuf) = size(buf.data, 1)

# it's important to define Base.similar so that range-indexing returns the
# right type, instead of just a bare array
Base.similar{T}(buf::SampleBuf, ::Type{T}, dims::Dims) = SampleBuf(Array(T, dims), samplerate(buf))
# TODO: we shouldn't need the `collect` once SIUnits supports LinSpace
domain(buf::SampleBuf) = collect(0:(nframes(buf)-1)) / samplerate(buf)


"""Get a pointer to the underlying data for the buffer. Will return a Ptr{T},
where T is the element type of the buffer. This is particularly useful for
passing to C libraries to fill the buffer"""
channelptr(buf::SampleBuf, channel) =
    pointer(buf.data) + (channel-1)*nframes(buf) * sizeof(eltype(buf))

# the index types that Base knows how to handle. Separate out those that index
# multiple results
typealias BuiltinMultiIdx Union{Colon,
                           Vector{Int},
                           Vector{Bool},
                           Range{Int}}
typealias BuiltinIdx Union{Int, BuiltinMultiIdx}
# the index types that will need conversion to built-in index types. Each of
# these needs a `toindex` method defined for it
typealias ConvertIdx{T1 <: SIQuantity, T2 <: Int} Union{T1,
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

# if the unit of the given value is the inverse of the sampling rate unit,
# the result should be unitless
# TODO: clearer error message when the given unit is not the inverse of the sampling rate
toindex(buf::SampleBuf, t::SIQuantity) = round(Int, t*samplerate(buf)) + 1

# indexing by vectors of SIQuantities not yet supported
# toindex{T <: SIUnits.SIQuantity}(buf::SampleBuf, I::Vector{T}) = Int[toindex(buf, i) for i in I]
toindex(buf::SampleBuf, I::Interval{Int}) = I.lo:I.hi
toindex{T <: SIQuantity}(buf::SampleBuf, I::Interval{T}) = toindex(buf, I.lo):toindex(buf, I.hi)

# AbstractArray interface methods
Base.size(buf::SampleBuf) = size(buf.data)
Base.linearindexing{T <: SampleBuf}(::Type{T}) = Base.LinearFast()
# this is the fundamental indexing operation needed for the AbstractArray interface
Base.getindex(buf::SampleBuf, i::Int) = buf.data[i];

# now we implement the methods that need to convert indices. luckily we only
# need to support up to 2D
Base.getindex(buf::SampleBuf, I::ConvertIdx) = buf[toindex(buf, I)]
Base.getindex(buf::SampleBuf, I1::ConvertIdx, I2::BuiltinIdx) = buf[toindex(buf, I1), I2]
Base.getindex(buf::SampleBuf, I1::BuiltinIdx, I2::ConvertIdx) = buf[I1, toindex(buf, I2)]
Base.getindex(buf::SampleBuf, I1::ConvertIdx, I2::ConvertIdx) = buf[toindex(buf, I1), toindex(buf, I2)]

function Base.setindex!(buf::SampleBuf, val, i::Int)
    buf.data[i] = val
end

# equality
import Base.==
==(buf1::SampleBuf, buf2::SampleBuf) =
    samplerate(buf1) == samplerate(buf2) &&
    buf1.data == buf2.data

Base.fft(buf::SampleBuf) = SampleBuf(fft(buf.data), nframes(buf)//samplerate(buf))
Base.ifft(buf::SampleBuf) = SampleBuf(ifft(buf.data), nframes(buf)//samplerate(buf))
