"""
Represents an O-output, I-input sample stream, which could be a physical device
like a sound card, a network audio stream, audio file, etc.

Subtypes should implement

* read
* write
"""
abstract SampleStream{IN, OUT, SR, T <: Real}

# audio interface methods

samplerate{IN, OUT, SR, T}(stream::SampleStream{IN, OUT, SR, T}) = SR
