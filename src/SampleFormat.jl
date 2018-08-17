export SignalFormat, IsSignal, NotSignal, samplerate, usamplerate, tomono,
    tostereo, ismono, isstereo, signal, tosamplerate, tochannels,
    promote_signals, promote_signal_by

"""
    SignalFormat(x)

Indicates whether an object is a signal and if so, what format it takes.

When `x` is a signal, returns `IsSignal{R,T}`, where R is a unitful samplerate
and T is the `eltype` (the bitrate of the signal).  All objects that are not
signals return `NotSignal()` (the default). The value of `R` should be passed
to `format` before passing it to `IsSignal` to regularize the units and
type.

When an object is a signal it is assumed the following methods are implemented:

* `tosamplerate` - convert the signal to have the given sample rate (units may
   change: e.g. from Hz for a time domain signal to seconds for a frequency
   domain signal).
* `Base.eltype` - expected to return `T` from `IsSignal{R,T}.
* `nchannels` - number of channels in the signal
* `nframes` - the known number of frames in the signal or `missing`.
* `tochannels` - convert the signal to the have the given number of
  channels, returning a lazy, read-only signal (may be made write only with
  `copy`).

To access samples of a source it can either be a child of `AbstractArray` or it
can implement `tosource`, to interpret its samples as a `SampleSource` object.
"""
abstract type SignalFormat end
SignalFormat(x) = NotSignal()
struct IsSignal{R,S} <: SignalFormat end
struct NotSignal <:SignalFormat end

"""
    SampledSignals.format(R)

Given a samplerate, (to be used as a type parameter for a signal) validate it
and place it in a canonical format. If no unit is specified the value is
assumed to be in `Hz`.
"""
format(R::Unitful.Frequency) = uconvert(Hz,float(R))
format(R::Quantity) = upreferred(float(R))
format(R::Number) = format(R*Hz)
format(R) = error("Do not know how to interpret $R as a sample rate.")

function checkformat(x)
    if format(usamplerate(x)) != usamplerate(x)
        error("Format of sample rate for $x is invalid. Ensure that "*
              "`usamplerate(x)` returns $(format(usamplerate(x))).")
    end
end

"""
    `usamplerate(x)`

The unitful samplerate of the signal; e.g. for a time-domain signal this
is a value in Hz as a `Unitful.Quantity`; for a frequency-domain signal
this is a vlaue in seconds as `Unitful.Quantity`.
"""
usamplerate(x) = usamplerate(x,SignalFormat(x))
usamplerate(x,::IsSignal{R}) where R = R
usamplerate(x,::NotSignal) = error("The value $x is not a signal.")

"""
    `samplerate(x)`

The sample rate of the signal in preferred units; for a time-domain signal
this is a value in Hz as a `Float64`; for a frequency-domain signal a value
in seconds as a `Float64`.
"""
samplerate(x) = samplerate(x,SignalFormat(x))
samplerate(x,::IsSignal{R}) where R = ustrip(upreferred(R))
samplerate(x,::NotSignal) = error("The value $x is not a signal.")

show_samplerate(x::Unitful.Frequency) = string(ustrip(upreferred(x)))*" Hz"
show_samplerate(x) = string(upreferred(x))
show_sampleunit(x::Unitful.Frequency) = "Hz"
show_sampleunit(x) = unit(upreferred(x))

"""
    tomono(x)

Mix all channels of x into a single mono-channel signal.
"""
tomono(x) = tochannels(x,1)


"""
    tostereo(x)

Spread a single channel signal into a stereo signal with identical channels.
"""
tostereo(x) = tochannels(x,2)

"""
   ismono(x)

True if the signal has one channel.
"""
ismono(x) = nchannels(x) == 1

"""
    isstereo(x)

True if the signal has two channels.
"""
isstereo(x) = tochannels(x) == 2

"""
    issignal(x)

True if an object is a signal, according to `SampledSignals`.
"""
issignal(x) = issignal(x,SignalFormat(x))
issignal(x,::IsSignal) = true
issignal(x,::NotSignal) = false

"""
    signal(x,samplerate)

Interpret the object `x` as a signal with the given sample rate. If not
specified the unit is assumed to be in Hz.

    signal(x,samplerate,::NotSignal)

Internally called signature of `signal` to interpret an object as a given
format.  The value of samplerate is always unitful.  This method should not be
called directly, but can be implemented for a specific type of `x` to define
how that object should be interpreted as a signal.
"""
signal(x,samplerate) = signal(x,inHz(samplerate)*Hz)
signal(x,samplerate::Quantity) = signal(x,samplerate,SignalFormat(x))
signal(x,samplerate,::IsSignal) = x
signal(x,smaplerate,::NotSignal) =
    error("Don't know how to turn $x into a signal.")

"""
    tosamplerate(x,samplerate)

Resample `x` to the given samplerate, interpretting as a signal (as per
`signal`) if necessary. If the samplerate is unitless the samplerate is assumed
to be Hz. This method can convert between different units: e.g.  from time
domain (sample rate in Hertz) to frequency domain (sample rate in seconds) and
vice versa.

To implement this for a new kind of signal `MyType` the following method
signature should be overwritten:

    tosamplerate(x,sr,::IsSignal)

This ensures that the fall-backs for handling non-signal objects remain intact.
"""
tosamplerate(x,samplerate) = tosamplerate(x,inHz(samplerate)*Hz)
tosamplerate(x,samplerate::Quantity) = tosamplerate(x,format(samplerate),SignalFormat(x))
tosamplerate(x,sr,::NotSignal) = tosamplerate(signal(x,sr),sr)

"""
   promote_signals(xs)

Interpret all objects as signals (as per `signal`) and coerce them to share the
same samplerate (as per `tosamplerate`) and channel count.
"""
function promote_signals(xs...)
    @assert any(issignal,xs) "At least one input must be a signal."

    R = maximum(samplerates(xs...))

    xs = tosamplerate.(signal.(xs,R),R)
    ch = maximum(nchannels.(xs))
    xs = tochannels.(xs,ch)
    xs
end

samplerates(x,xs...) =
    (samplerates_head(x,SignalFormat(x))...,samplerates(xs...)...)
samplerates() = ()
samplerates_head(x,::NotSignal) = ()
samplerates_head(x,::IsSignal{R}) where R = (R,)

"""
    promote_signal(x;by)

Interpret `x` as a signal (as per `signal`) and coerce it to share the same
sample rate and channel count as `by`. You can broadcast this function to
promote multiple signals.
"""
function promote_signal(x;by)
    R = usamplerate(by)

    # be efficient about when to convert channels (resample with the smallest
    # number of channels possible)
    if nchannels(by) < nchannels(x)
        x = tochannels(x,nchannels(by))
    end
    x = tosamplerate(signal(x,R),R)
    if nchannels(by) > nchannels(x)
        x = tochannels(x,nchannels(by))
    end
    x
end
