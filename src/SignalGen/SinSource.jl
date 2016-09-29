"""
SinSource is a multi-channel sine-tone signal generator.
"""
type SinSource{T} <: SampleSource
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

Base.eltype{T}(::SinSource{T}) = T
nchannels(source::SinSource) = length(source.freqs)
samplerate(source::SinSource) = source.samplerate

function unsafe_read!(source::SinSource, buf::Array, frameoffset, framecount)
    inc = 2pi / samplerate(source)
    for ch in 1:nchannels(buf)
        f = source.freqs[ch]
        ph = source.phases[ch]
        for i in 1:framecount
            buf[i+frameoffset, ch] = sin(ph)
            ph += f
        end
        source.phases[ch] = ph
    end

    framecount
end
