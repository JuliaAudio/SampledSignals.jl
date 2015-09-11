module SampleTypes

using SIUnits
# TODO: add kHz once my PR is merged into SIUnits
using SIUnits.ShortUnits: ns, ms, µs, s, Hz, MHz, GHz, THz

"""A Real amount of time, measured in seconds"""
typealias RealTime{T <: Real} quantity(T, Second)

export SampleBuf, TimeSampleBuf, FrequencySampleBuf
export SampleSouce, SampleSink, read, write
export DummySampleSource, DummySampleSink, simulate_input
export DSPNode
# general methods for types in SampleTypes
export samplerate, nchannels
# re-export the useful units
# TODO: add kHz once my PR is merged into SIUnits
export ns, ms, µs, s, Hz, MHz, GHz, THz


include("SampleBuf.jl")
include("SampleStream.jl")
include("DummySampleStream.jl")
include("DSPNode.jl")

end # module
