__precompile__()

module SampledSignals

using SIUnits
using SIUnits.ShortUnits: ns, ms, µs, s, Hz, kHz, MHz, GHz, THz
using SIUnits: SIQuantity
using FixedPointNumbers
using Compat
# if/when we drop 0.4 support we can remove UTF8String and just call it "String".
# we'll also be able to use view without importing it from Compat
import Compat: view, UTF8String
@compat import Base.show

export SampleBuf
export SampleSource, SampleSink
export SampleRate
export DummySampleSource, DummySampleSink, simulate_input
export ResampleSink, ReformatSink, DownMixSink, UpMixSink
export SampleBufSource, SampleBufSink
export SinSource
export Interval, ..
# general methods for types in SampledSignals
export samplerate, nchannels, nframes, domain, channelptr, blocksize
# re-export the useful units
export ns, ms, µs, s, Hz, kHz, MHz, GHz, THz

typealias HertzQuantity{T} SIUnits.SIQuantity{T,0,0,-1,0,0,0,0,0,0}
typealias SecondsQuantity{T} SIUnits.SIQuantity{T,0,0,1,0,0,0,0,0,0}

include("Interval.jl")
include("SampleBuf.jl")
include("SampleStream.jl")
include("DummySampleStream.jl")
include("SignalGen/SinSource.jl")
include("WAVDisplay.jl")
include("deprecated.jl")

end # module
