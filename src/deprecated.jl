function unsafe_read! end
function unsafe_write end

# fallback function for libraries using the old unsafe_read! function
const read_depwarned = Set{Type}()
function unsafe_read!{T <: SampleSource}(src::T, buf::Array, frameoffset, framecount)
    if !(T in read_depwarned)
        push!(read_depwarned, T)
        warn("""`unsafe_read!(src::$T, buf::Array, frameoffset, framecount)` not defined,
                falling back to deprecated `unsafe_read!(src::$T, buf::SampleBuf)`. Please
                check the SampledSignals README for the new API""")
    end

    tmp = SampleBuf(Array(eltype(src), framecount, nchannels(src)), samplerate(src))
    n = unsafe_read!(src, tmp)
    buf[(1:framecount)+frameoffset, :] = view(tmp.data, :, :)

    n
end

# fallback function for libraries using the old unsafe_write function
const write_depwarned = Set{Type}()
function unsafe_write{T <: SampleSink}(sink::T, buf::Array, frameoffset, framecount)
    if !(T in write_depwarned)
        push!(write_depwarned, T)
        warn("""`unsafe_write(src::$T, buf::Array, frameoffset, framecount)` not defined,
                falling back to deprecated `unsafe_write(src::$T, buf::SampleBuf)`. Please
                check the SampledSignals README for the new API""")
    end

    tmp = SampleBuf(buf[(1:framecount)+frameoffset, :], samplerate(sink))
    unsafe_write(sink, tmp)
end
