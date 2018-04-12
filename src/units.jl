const frames = Hz*s
const FrameQuant = DimensionlessQuantity

"""
    inframes(quantity,rate)

Translate the given quantity (usually a time) to a (unitless) number of frames,
given a particular samplerate.

# Example

> inframes(0.5s,44100Hz)
22050

"""
inframes(time,rate) = floor(Int,inseconds(time)*inHz(rate))
inframes(frame::FrameQuant,rate) = ustrip(frame)
inframes(frame::FrameQuant) = ustrip(frame)
inframes(frame::Quantity) = error("Unknown sample rate")
inframes(frame::Number) = frame

"""
    inHz(quantity)

Translate a particular quantity (usually a frequency) to a value in Hz.

# Example

> inHz(1.0kHz)
1000.0

"""
inHz(x::Quantity) = ustrip(uconvert(Hz,x))
inHz(x::Number) = x

"""
   inseconds(quantity,[rate])

Translate a particular quantity (usually a time) to a value in seconds.

For some units (e.g. frames) you will need to specify a sample rate:

# Examples
> inseconds(50.0ms)
0.05

> inseconds(441frames,44100Hz)
0.01

"""
inseconds(x::Quantity) = ustrip(uconvert(s,x))
inseconds(x::Number) = x

inseconds(x,rate::Quantity) = inseconds(x,inHz(rate))
inseconds(x::FrameQuant,rate::Real) = (ustrip(x) / rate)
inseconds(x::Quantity,rate::Real) = ustrip(uconvert(s,x))
inseconds(x::Number,rate::Real) = inseconds(x)
