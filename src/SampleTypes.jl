module SampleTypes

using SIUnits
using SIUnits.ShortUnits: ns, ms, µs, s, Hz, kHz, MHz, GHz, THz

"""A Real amount of time, measured in seconds"""
typealias RealTime{T <: Real} quantity(T, Second)
"""A Real frequency, measured in Hz"""
typealias RealFrequency{T <: Real} quantity(T, Hertz)

export SampleBuf, TimeSampleBuf, FrequencySampleBuf
export SampleSouce, SampleSink, read, write
export DummySampleSource, DummySampleSink, simulate_input
export DSPNode
export Interval, ..
# general methods for types in SampleTypes
export samplerate, nchannels, nframes
# re-export the useful units
export ns, ms, µs, s, Hz, kHz, MHz, GHz, THz


include("Interval.jl")
include("SampleBuf.jl")
include("SampleStream.jl")
include("DummySampleStream.jl")
include("DSPNode.jl")

end # module
