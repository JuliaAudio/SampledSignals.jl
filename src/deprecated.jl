function unsafe_read! end
function unsafe_write end

# apparently stacktrace doesn't exist on 0.4, so too bad, 0.4 users don't get
# stack traces on their deprecation warnings
if !isdefined(:stacktrace)
    stacktrace() = []
end

# fallback function for libraries using the old unsafe_read! function
const read_depwarned = Set{Type}()
function unsafe_read!{T <: SampleSource}(src::T, buf::Array, frameoffset, framecount)
    if !(T in read_depwarned)
        push!(read_depwarned, T)
        warn("""`unsafe_read!(src::$T, buf::Array, frameoffset, framecount)` not defined,
                falling back to deprecated `unsafe_read!(src::$T, buf::SampleBuf)`. Please
                check the SampledSignals README for the new API""")
        map(println, stacktrace())
    end

    tmp = SampleBuf(Array{eltype(src)}(framecount, nchannels(src)), samplerate(src))
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
        map(println, stacktrace())
    end

    tmp = SampleBuf(buf[(1:framecount)+frameoffset, :], samplerate(sink))
    unsafe_write(sink, tmp)
end

const unit_depwarned = Ref(false)
function SampleBuf(arr::Array, sr::HertzQuantity)
    if !unit_depwarned[]
        warn("Samplerates with units are deprecated. Switch to plain floats")
        map(println, stacktrace())
        unit_depwarned[] = true
    end
    SampleBuf(arr, float(sr))
end

function SampleBuf(T::Type, sr::HertzQuantity, len::SecondsQuantity)
    if !unit_depwarned[]
        warn("Samplerates with units are deprecated. Switch to plain floats")
        map(println, stacktrace())
        unit_depwarned[] = true
    end
    SampleBuf(T, float(sr), len)
end

function SampleBuf(T::Type, sr::HertzQuantity, args...)
    if !unit_depwarned[]
        warn("Samplerates with units are deprecated. Switch to plain floats")
        map(println, stacktrace())
        unit_depwarned[] = true
    end
    SampleBuf(T, float(sr), args...)
end

# wrapper for samplerate that converts to floating point from unitful values
# and prints a depwarn. We use this internally to keep backwards compatibility,
# but it can be removed and replaced with normal `samplerate` calls when we
# remove compatibility
compat_samplerate(x) = warn_if_unitful(samplerate(x))

warn_if_unitful(x) = x
function warn_if_unitful(x::SIQuantity)
    if !unit_depwarned[]
        warn("Samplerates with units are deprecated. Switch to plain floats")
        map(println, stacktrace())
        unit_depwarned[] = true
    end
    float(x)
end

function SinSource{T <: SIQuantity}(eltype, samplerate::SIQuantity, freqs::Array{T})
    SinSource(eltype, warn_if_unitful(samplerate), map(float, freqs))
end

function SinSource(eltype, samplerate::SIQuantity, freqs::Array)
    SinSource(eltype, warn_if_unitful(samplerate), freqs)
end

function SinSource{T <: SIQuantity}(eltype, samplerate, freqs::Array{T})
    SinSource(eltype, samplerate, map(warn_if_unitful, freqs))
end
