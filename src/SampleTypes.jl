module SampleTypes

using SIUnits
using SIUnits.ShortUnits

"""A Real amount of time, measured in seconds"""
typealias RealTime{T <: Real} quantity(T, Second)

export SampleBuf, TimeSampleBuf, FrequencySampleBuf
export SampleStream, read, write
export DSPNode
# re-export the useful units
export ns, ms, µs, s, Hz, kHz, MHz, GHz, THz

export DummySampleStream, simulate_input

include("SampleBuf.jl")
include("SampleStream.jl")
include("DummySampleStream.jl")
include("DSPNode.jl")

end # module
