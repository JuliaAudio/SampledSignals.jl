__precompile__()

module SampledSignals

export AbstractSampleBuf, SampleBuf, SpectrumBuf
export SampleSource, SampleSink
export SampleRate
export ResampleSink, ReformatSink, DownMixSink, UpMixSink
export SampleBufSource, SampleBufSink
export SinSource
export Interval, ..
# general methods for types in SampledSignals
export samplerate, samplerate!, nchannels, nframes, domain, channelptr, blocksize
export mix!, mix, mono!, mono
# re-export the useful units
export ns, ms, µs, s, Hz, kHz, MHz, GHz, THz
export PCM8Sample, PCM16Sample, PCM24Sample, PCM32Sample, PCM64Sample

using SIUnits
using SIUnits.ShortUnits: ns, ms, µs, s, Hz, kHz, MHz, GHz, THz
using SIUnits: SIQuantity
using FixedPointNumbers
using DSP

import Base: show

const HertzQuantity{T} = SIUnits.SIQuantity{T,0,0,-1,0,0,0,0,0,0}
const SecondsQuantity{T} = SIUnits.SIQuantity{T,0,0,1,0,0,0,0,0,0}

const PCM8Sample = Fixed{Int8, 7}
const PCM16Sample = Fixed{Int16, 15}
const PCM24Sample = Fixed{Int32, 23} # assume right-aligned data
const PCM32Sample = Fixed{Int32, 31}
const PCM64Sample = Fixed{Int64, 63}

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
