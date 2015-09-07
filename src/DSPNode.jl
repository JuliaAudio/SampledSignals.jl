"""
A signal processing node. These nodes can be wired together in a Sample
processing graph. Each node can have a number of input and output AudioStreams.
"""
abstract DSPNode{SR <: Real, T <: Number}
