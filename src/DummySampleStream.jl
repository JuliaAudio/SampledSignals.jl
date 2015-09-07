type DummySampleStream{O, I, SR <: Real, T <: Real} <: SampleStream{O, I, SR, T}
    outbuf::Array{T, 2}
    inbuf::Array{T, 2}
    DummySampleStream{O, I, SR, T}() = new(Array(T, (0, O)), Array(T, (0, I)))
end

"""
Simulate receiving input on the dummy stream. This adds data to the internal
buffer, so that when client code reads from the stream they receive this data.
This will also wake up any tasks that are blocked waiting for data from the
stream.
"""
function simulate_input(stream::DummySampleStream{O, I, SR, T}, data::Array{T, 2})
    if size(data, 2) != I
        error("Simulated data channel count must match stream input count")
    end
    inbuf = vcat(inbuf, data)
end
