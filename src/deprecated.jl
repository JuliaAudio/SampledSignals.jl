function unsafe_read! end
function unsafe_write end

# fallback function for libraries using the old unsafe_read! function
const read_depwarned = Set{Type}()
function Base.read!{T <: SampleSource}(src::T, buf::Array)
    if !(T in read_depwarned)
        push!(read_depwarned, T)
        warn("""`Base.read!` not defined for type $T, falling back to deprecated
                `unsafe_read!`. Please check the SampledSignals README for the new API""")
    end

    unsafe_read!(src, SampleBuf(buf, samplerate(src)))
end

# fallback function for libraries using the old unsafe_write function
const write_depwarned = Set{Type}()
function Base.write{T <: SampleSink}(sink::T, buf::Array)
    if !(T in write_depwarned)
        push!(write_depwarned, T)
        warn("""`Base.write` not defined for type $T, falling back to deprecated
                `unsafe_write`. Please check the SampledSignals README for the new API""")
    end

    unsafe_write(sink, SampleBuf(buf, samplerate(sink)))
end
