import SampledSignals: blocksize, samplerate, nchannels
import Base: eltype

# used in SampleStream tests to test blocked reading
type BlockedSampleSource <: SampleSource
    framesleft::Int
end

blocksize(src::BlockedSampleSource) = 16
samplerate(src::BlockedSampleSource) = 48000Hz
eltype(src::BlockedSampleSource) = Float32
nchannels(src::BlockedSampleSource) = 2

function Base.read!(src::BlockedSampleSource, buf::Array)
    @test nframes(buf) == blocksize(src)
    toread = min(nframes(buf), src.framesleft)
    for ch in 1:nchannels(buf), i in 1:toread
        buf[i, ch] = i * ch
    end
    src.framesleft -= toread

    toread
end
