"""
    SinSource(eltype, samplerate, freqs)

SinSource is a multi-channel sine-tone signal generator. `freqs` can be an
array of frequencies for a multi-channel source, or a single frequency for a
mono source.
"""
mutable struct SinSource{T} <: SampleSource
    samplerate::Float64
    freqs::Vector{Float64} # in radians/sample
    phases::Vector{Float64}
end

function SinSource(eltype, samplerate, freqs::Array)
    # convert frequencies from cycles/sec to rad/sample
    radfreqs = map(f->2pi*f/samplerate, freqs)
    SinSource{eltype}(Float64(samplerate), radfreqs, zeros(length(freqs)))
end

# also allow a single frequency
SinSource(eltype, samplerate, freq::Real) = SinSource(eltype, samplerate, [freq])

Base.eltype(::SinSource{T}) where T = T
SignalBase.nchannels(source::SinSource) = length(source.freqs)
SignalBase.framerate(source::SinSource) = source.samplerate

function unsafe_read!(source::SinSource, buf::Array, frameoffset, framecount)
    inc = 2pi / framerate(source)
    for ch in 1:nchannels(buf)
        f = source.freqs[ch]
        ph = source.phases[ch]
        for i in 1:framecount
            buf[i+frameoffset, ch] = sin.(ph)
            ph += f
        end
        source.phases[ch] = ph
    end

    framecount
end
