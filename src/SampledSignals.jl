__precompile__()

module SampledSignals

using SIUnits
using SIUnits.ShortUnits: ns, ms, µs, s, Hz, kHz, MHz, GHz, THz
using SIUnits: SIQuantity
using Compat
# if/when we drop 0.4 support we can remove UTF8String and just call it "String".
# we'll also be able to use view without importing it from Compat
import Compat: view, UTF8String

export SampleBuf
export SampleSource, SampleSink
export SampleRate
export DummySampleSource, DummySampleSink, simulate_input
export ResampleSink, ReformatSink, DownMixSink, UpMixSink
export SampleBufSource, SampleBufSink
export SinSource
export Interval, ..
# general methods for types in SampledSignals
export samplerate, nchannels, nframes, domain, channelptr
# re-export the useful units
export ns, ms, µs, s, Hz, kHz, MHz, GHz, THz


include("Interval.jl")
include("SampleBuf.jl")
include("SampleStream.jl")
include("DummySampleStream.jl")
include("SignalGen/SinSource.jl")

end # module
