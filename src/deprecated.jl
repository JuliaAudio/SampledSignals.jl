import Base: @deprecate

@deprecate SpectrumBuf(x::Array, sr::Real) SampleBuf(x,sr,:freq)
@deprecate SpectrumBuf(::Type{T} where T, sr::Real, dims...) SampleBuf(T,sr,:freq, dims...)
@deprecate samplerate!(buf::SampleBuf,sr::Real) SampleBuf(Array(buf),sr)
