"""
SinSource is a multi-channel sine-tone signal generator. Frequency and samplerate
must have the same units (if any).
"""
# phase will have the inverse units (probably s) to freq and samplerate (probably Hz)
type SinSource{T, U, PU} <: SampleSource
    samplerate::U
    freqs::Vector{U}
    phase::PU
end

function SinSource(eltype, samplerate, freqs::Array)
    U = typeof(samplerate)
    phase = zero(inv(samplerate))
    PU = typeof(phase)
    SinSource{eltype, U, PU}(samplerate, freqs, phase)
end

# also allow a single frequency
SinSource(eltype, samplerate, freq::Number) = SinSource(eltype, samplerate, [freq])

Base.eltype{T, U, PU}(::SinSource{T, U, PU}) = T
nchannels(source::SinSource) = length(source.freqs)
samplerate(source::SinSource) = source.samplerate

function unsafe_read!(source::SinSource, buf::SampleBuf)
    inc = 2pi / samplerate(source)
    for ch in 1:nchannels(buf)
        f = source.freqs[ch]
        for i in 1:nframes(buf)
            buf[i, ch] = sin((source.phase + (i-1)*inc)*f)
        end
    end
    source.phase += nframes(buf) * inc

    nframes(buf)
end
