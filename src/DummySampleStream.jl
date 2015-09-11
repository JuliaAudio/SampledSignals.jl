type DummySampleSource{N, SR, T <: Real} <: SampleSource{N, SR, T}
    buf::Array{T, 2}
    DummySampleSource() = new(Array(T, (0, N)))
end

type DummySampleSink{N, SR, T <: Real} <: SampleSink{N, SR, T}
    buf::Array{T, 2}
    DummySampleSink() = new(Array(T, (0, N)))
end

"""
Simulate receiving input on the dummy source This adds data to the internal
buffer, so that when client code reads from the source they receive this data.
This will also wake up any tasks that are blocked waiting for data from the
stream.
"""
function simulate_input{N, SR, T}(src::DummySampleSource{N, SR, T}, data::Array{T})
    if size(data, 2) != N
        error("Simulated data channel count must match stream input count")
    end
    src.buf = vcat(src.buf, data)
end

# stream interface methods

import Base.write
"""
Writes the sample buffer to the sample sink. If no other writes have been
queued the Sample will be played immediately. If a previously-written buffer is
in progress the signal will be queued. To mix multiple signal see the `play`
function. Currently we only implement the non-resampling, non-converting method.
"""
function write{N, SR, T}(sink::DummySampleSink{N, SR, T}, buf::TimeSampleBuf{N, SR, T})
    # TODO: probably should check channels here instead of using dispatch so we can give a better error message
    sink.buf = vcat(sink.buf, buf.data)
end

import Base.read
"""
Reads from the given stream and returns a TimeSampleBuf with the data. The
amount of data to read can be given as an integer number of samples or a
real-valued number of seconds.
"""
function read{N, SR, T}(src::DummySampleSource{N, SR, T}, samples::Integer)
    retdata = src.buf[1:samples, :]
    src.buf = src.buf[(samples+1):end, :]
    TimeSampleBuf{N, SR, T}(retdata)
end
function read{N, SR, T}(src::DummySampleSource{N, SR, T}, seconds::RealTime)
    samples = round(Int, seconds.val * SR)
    read(src, samples)
end
