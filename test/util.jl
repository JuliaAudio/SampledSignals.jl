import SampledSignals: blocksize, samplerate, nchannels, unsafe_read!
import Base: eltype

# used in SampleStream tests to test blocked reading
type BlockedSampleSource <: SampleSource
    framesleft::Int
end

blocksize(src::BlockedSampleSource) = 16
samplerate(src::BlockedSampleSource) = 48000Hz
eltype(src::BlockedSampleSource) = Float32
nchannels(src::BlockedSampleSource) = 2

function unsafe_read!(src::BlockedSampleSource, buf::Array, frameoffset, framecount)
    @test framecount == blocksize(src)
    toread = min(framecount, src.framesleft)
    for ch in 1:nchannels(buf), i in 1:toread
        buf[i+frameoffset, ch] = i * ch
    end
    src.framesleft -= toread

    toread
end
