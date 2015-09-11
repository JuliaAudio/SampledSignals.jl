"""
Represents a sample stream, which could be a physical device like a sound card,
or a network audio stream, audio file, etc.
"""
abstract SampleSource{N, SR, T <: Real}
abstract SampleSink{N, SR, T <: Real}

# audio interface methods

samplerate{N, SR, T}(stream::SampleSource{N, SR, T}) = SR
samplerate{N, SR, T}(stream::SampleSink{N, SR, T}) = SR
nchannels{N, SR, T}(stream::SampleSource{N, SR, T}) = N
nchannels{N, SR, T}(stream::SampleSink{N, SR, T}) = N
