type DummySampleStream{IN, OUT, SR, T <: Real} <: SampleStream{IN, OUT, SR, T}
    outbuf::Array{T, 2}
    inbuf::Array{T, 2}
    DummySampleStream() = new(Array(T, (0, OUT)), Array(T, (0, IN)))
end

"""
Simulate receiving input on the dummy stream. This adds data to the internal
buffer, so that when client code reads from the stream they receive this data.
This will also wake up any tasks that are blocked waiting for data from the
stream.
"""
function simulate_input{IN, OUT, SR, T}(stream::DummySampleStream{IN, OUT, SR, T}, data::Array{T, 2})
    if size(data, 2) != IN
        error("Simulated data channel count must match stream input count")
    end
    stream.inbuf = vcat(stream.inbuf, data)
end

function simulate_input{OUT, SR, T}(stream::DummySampleStream{1, OUT, SR, T}, data::Vector{T})
    stream.inbuf = vcat(stream.inbuf, data)
end

import Base.write
"""
Writes the sample buffer to the sample stream. If no other writes have been
queued the Sample will be played immediately. If a previously-written buffer is
in progress the signal will be queued. To mix multiple signal see the `play`
function. Currently we only implement the non-resampling, non-converting method.
"""
function write{IN, OUT, SR, T}(stream::DummySampleStream{IN, OUT, SR, T}, buf::TimeSampleBuf{OUT, SR, T})
    stream.outbuf = vcat(stream.outbuf, buf.data)
end

import Base.read
"""
Reads from the given stream and returns a TimeSampleBuf with the data. The
amount of data to read can be given as an integer number of samples or a
real-valued number of seconds.
"""
function read{IN, OUT, SR, T}(stream::DummySampleStream{IN, OUT, SR, T}, samples::Integer)
    retdata = stream.inbuf[1:samples, :]
    stream.inbuf = stream.inbuf[(samples+1):end, :]
    TimeSampleBuf{IN, SR, T}(retdata)
end
function read{IN, OUT, SR, T}(stream::DummySampleStream{IN, OUT, SR, T}, seconds::RealTime)
    samples = round(Int, seconds.val * SR)
    read(stream, samples)
end
