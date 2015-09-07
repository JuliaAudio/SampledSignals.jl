module SampleTypes

using SIUnits

"""A Real amount of time, measured in seconds"""
typealias RealTime{T <: Real} quantity(T, Second)

export AbstractSampleBuf, TimeSampleBuf, FrequencySampleBuf
export SampleStream
export DSPNode

"""
Represents a multi-channel sample buffer. The wrapped data is a MxN array with M
samples and N channels. Signals in the time domain are represented by the
concrete type TimeSampleBuf and frequency-domain signals are represented by
FrequencySampleBuf. So a 1-second stereo audio buffer sampled at 44100Hz with
32-bit floating-point samples in the time domain would have the type
TimeSampleBuf{2, 44100.0, Float32}.
"""
abstract AbstractSampleBuf{N, SR, T <: Number}

"A time-domain signal. See AbstractSampleBuf for details"
type TimeSampleBuf{N, SR, T} <: AbstractSampleBuf{N, SR, T}
    data::Array{T, N}
end

"A frequency-domain signal. See AbstractSampleBuf for details"
type FrequencySampleBuf{N, SR, T} <: AbstractSampleBuf{N, SR, T}
    data::Array{T, N}
end

"""
Represents an O-output, I-input sample stream, which could be a physical device
like a sound card, a network audio stream, audio file, etc.
"""
abstract SampleStream{O, I, SR <: Real, T <: Real}

"""
A signal processing node. These nodes can be wired together in a Sample
processing graph. Each node can have a number of input and output AudioStreams.
"""
abstract DSPNode{SR <: Real, T <: Number}

"""
Writes the sample buffer to the sample stream. If no other writes have been
queued the Sample will be played immediately. If a previously-written buffer is
in progress the signal will be queued. To mix multiple signal see the `play`
function.
"""
import Base.write
function write(stream::SampleStream{SR_S, T_S}, buf::TimeSampleBuf{SR_D, T_D})
end

"""
Reads from the given stream and returns a TimeSampleBuf with the data. The
amount of data to read can be given as an integer number of samples or a
real-valued number of seconds.
"""
import Base.read
function read(stream::AudioStream, samples::Integer)
end
function read(stream::AudioStream, seconds::RealTime)
end

end # module
