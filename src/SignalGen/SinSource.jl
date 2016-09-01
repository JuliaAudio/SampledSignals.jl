"""
SinSource is a multi-channel sine-tone signal generator. Frequency and samplerate
must have the same units (if any).
"""
# TODO: type instabilities in SIUnits.jl were causing major slowdowns here, so
# for now I'm just stripping the units for the calculations and phase storage
# phase will have the inverse units (probably s) to freq and samplerate (probably Hz)
type SinSource{T, U} <: SampleSource
    samplerate::U
    freqs::Vector{U}
    phase::Float64
end

function SinSource(eltype, samplerate, freqs::Array)
    U = typeof(samplerate)
    SinSource{eltype, U}(samplerate, freqs, 0.0)
end

# also allow a single frequency
SinSource(eltype, samplerate, freq::Number) = SinSource(eltype, samplerate, [freq])

Base.eltype{T, U}(::SinSource{T, U}) = T
nchannels(source::SinSource) = length(source.freqs)
samplerate(source::SinSource) = source.samplerate

function Base.read!(source::SinSource, buf::Array)
    inc = 2pi / float(samplerate(source))
    for ch in 1:nchannels(buf)
        f = float(source.freqs[ch])
        for i in 1:nframes(buf)
            buf[i, ch] = sin((source.phase + (i-1)*inc)*f)
        end
    end
    source.phase += nframes(buf) * inc

    nframes(buf)
end
