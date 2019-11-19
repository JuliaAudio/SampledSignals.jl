const frames = Hz*s
const FrameQuant = DimensionlessQuantity

"""
    inframes([Type,]quantity[, rate])

Translate the given quantity to a (unitless) number of time or frequency frames,
given a particular samplerate. Note that this isn't quantized to integer numbers
of frames. If given a `Type`, the result will first be coerced to the given type.

If the given quantity is Unitful, we use the given units. If it is not we assume
it is already a value in frames.

# Example

julia> inframes(0.5s, 44100Hz)
22050.0

julia> inframes(1000Hz, 2048/44100Hz)
46.439909297052154

"""
inframes(::Type{T}, frame::FrameQuant, rate=nothing) where T <: Integer =
    round(T, ustrip(uconvert(frames, frame)))
inframes(frame::FrameQuant, rate=nothing) = ustrip(uconvert(frames, frame))
inframes(::Type{T}, time::Unitful.Time, rate) where T <: Integer =
    round(T, inseconds(time)*inHz(rate))
inframes(time::Unitful.Time, rate) = inseconds(time)*inHz(rate)
inframes(::Type{T}, freq::Unitful.Frequency, rate) where T <: Integer =
    round(T, inHz(freq)*inseconds(rate))
inframes(freq::Unitful.Frequency, rate) = inHz(freq)*inseconds(rate)
inframes(::Type, frame::Unitful.AbstractQuantity) = error("Unknown sample rate")
inframes(frame::Unitful.AbstractQuantity) = error("Unknown sample rate")
inframes(::Type{T}, frame::Real) where T = T(frame)
inframes(frame::Real) = frame

"""
    inHz(quantity[, rate])

Translate a particular quantity (usually a frequency) to a (unitless) value in
Hz.

If the given quantity is Unitful, we use the given units. If it is not we assume
it is already a value in Hz.

For some units (e.g. frames) you will need to specify a sample rate:

# Example

julia> inHz(1.0kHz)
1000.0

"""
inHz(x::Unitful.Frequency, rate=nothing) = ustrip(uconvert(Hz, x))
inHz(x::FrameQuant) = error("Unknown sample rate")
# assume we have a spectrum buffer with a sample rate in seconds
inHz(x::FrameQuant, rate) = inHz(inframes(x) / rate)
inHz(x::Real, rate) = x
inHz(x::Real) = x

"""
   inseconds(quantity[, rate])

Translate a particular quantity (usually a time) to a (unitless) value in
seconds.

If the given quantity is Unitful, we use the given units. If it is not we assume
it is already a value in seconds.

For some units (e.g. frames) you will need to specify a sample rate:

# Examples
julia> inseconds(50.0ms)
0.05

julia> inseconds(441frames, 44100Hz)
0.01

"""
inseconds(x::Unitful.Time, rate=nothing) = ustrip(uconvert(s,x))
inseconds(x::FrameQuant) = error("Unknown sample rate")
# assume we have a time buffer with sample rate in hz
inseconds(x::FrameQuant, rate) = inseconds(inframes(x) / rate)
inseconds(x::Real, rate) = x
inseconds(x::Real) = x

# inseconds(x, rate::Quantity) = inseconds(x,inHz(rate))
# inseconds(x::FrameQuant, rate::Real) = (ustrip(x) / rate)
# inseconds(x::Quantity, rate::Real) = ustrip(uconvert(s,x))
