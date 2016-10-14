__precompile__()

module SampledSignals

using SIUnits
using SIUnits.ShortUnits: ns, ms, µs, s, Hz, kHz, MHz, GHz, THz
using SIUnits: SIQuantity
using FixedPointNumbers
using DSP
using Compat
# if/when we drop 0.4 support we can remove UTF8String and just call it "String".
# we'll also be able to use view without importing it from Compat
import Compat: view, UTF8String
@compat import Base.show

export AbstractSampleBuf, SampleBuf, SpectrumBuf
export SampleSource, SampleSink
export SampleRate
export ResampleSink, ReformatSink, DownMixSink, UpMixSink
export SampleBufSource, SampleBufSink
export SinSource
export Interval, ..
# general methods for types in SampledSignals
export samplerate, samplerate!, nchannels, nframes, domain, channelptr, blocksize
# re-export the useful units
export ns, ms, µs, s, Hz, kHz, MHz, GHz, THz
export PCM8Sample, PCM16Sample, PCM24Sample, PCM32Sample

typealias HertzQuantity{T} SIUnits.SIQuantity{T,0,0,-1,0,0,0,0,0,0}
typealias SecondsQuantity{T} SIUnits.SIQuantity{T,0,0,1,0,0,0,0,0,0}

typealias PCM8Sample Fixed{Int8, 7}
typealias PCM16Sample Fixed{Int16, 15}
typealias PCM24Sample Fixed{Int32, 23}
typealias PCM32Sample Fixed{Int32, 31}

include("Interval.jl")
include("SampleBuf.jl")
include("SampleStream.jl")
include("SignalGen/SinSource.jl")
include("WAVDisplay.jl")
include("deprecated.jl")

function __init__()
    if isdefined(Main, :IJulia) && Main.IJulia.inited
        embed_javascript()
    end
end

end # module
