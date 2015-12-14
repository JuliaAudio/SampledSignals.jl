# SampleTypes

[![Build Status](https://travis-ci.org/JuliaAudio/SampleTypes.jl.svg?branch=master)] (https://travis-ci.org/JuliaAudio/SampleTypes.jl)
[![codecov.io] (http://codecov.io/github/JuliaAudio/SampleTypes.jl/coverage.svg?branch=master)] (http://codecov.io/github/JuliaAudio/SampleTypes.jl?branch=master)

**Note - this is very much a work in progress and not ready for public use**

SampleTypes is a collection of types intended to be used on multichannel sampled signals like audio or radio data, to provide better interoperability between packages that read data from files or streams, DSP packages, and output and display packages.

SampleTypes provides several types to stream and store sampled data: `SampleBuf`, `TimeSampleBuf`, `FrequencySampleBuf`, `SampleSource`, `SampleSink` and also an `Interval` type that can be used to represent contiguous ranges using a convenient `a..b` syntax, this feature is copied mostly from the [AxisArrays](https://github.com/mbauman/AxisArrays.jl) package, which also inspired much of the implementation of this package.

We also use the [SIUnits](https://github.com/keno/SIUnits.jl) package to enable indexing using real-world units like seconds or hertz. `SampleTypes` re-exports the relevant `SIUnits` units (`ns`, `ms`, `µs`, `s`, `Hz`, `kHz`, `MHz`, `GHz`, `THz`) so you don't need to import `SIUnits` explicitly.

## Types

### SampleBuf

`SampleBuf` is an abstract type representing multichannel, regularly-sampled data, providing handy indexing operations. It subtypes AbstractArray and should be drop-in compatible with raw arrays, with the exception that indexing with a linear range will result in a 2D Nx1 result instead of a 1D Vector. Also when the first index is a scalar (such as `buf[35, 1:2]`) the returned object will be a 1-frame 2-channel buffer, instead of dropping the scalar-index axis. The two main advantages of SampleBufs are they are sample-rate aware and that they support indexing with real-world units like seconds or hertz (depending on the domain). To create a custom subtype of `SampleBuf` you only need to define `Base.similar` so that the result of indexing operations and arithmetic will be wrapped correctly and `SampleTypes.toindex` which defines how a unit quantity should be mapped to an index. The rest of the methods are defined on `SampleBuf` so they should Just Work.

SampleTypes also implements two concrete `SampleBuf` subtypes for commonly-used domains:

* `TimeSampleBuf`, which supports indexing in seconds
* `FrequencySampleBuf` which supports indexing in hertz

## SampleSource

A source of samples, which might for instance represent a microphone input. The `read` method just gives you a single frame (an 1xN N-channel `TimeSampleBuf`), but you can also read an integer number of samples or an amount of time given in seconds. This package includes the `DummySampleSource` concrete type that is useful for testing the stream interface.

## SampleSink

A sink for samples to be written to, for instance representing your laptop speakers. The main method used here is `write` which writes a `SampleBuf` to a `SampleSink`. This package includes the `DummySampleSink` concrete type that is useful for testing the stream interface.

## Sticky Design Issues

There are a number of issues that I'm still in the process of figuring out:

### Keeping track of sample rate

We want to be able to go between domains (e.g. time/frequency) without losing the exact sample rate, so just keeping a floating point SR in the local domain is problematic. One option is to use `Rational`s for the SR. Currently we keep track of the time-domain sample rate even in the frequency domain and calculate the frequencies assuming the length of the buffer is the length of the FFT. That doesn't work if you want to look at a slice of the frequency-domain buffer.

### Complexity and Symmetry

A real-valued time-domain buffer becomes a symmetric complex frequency-domain buffer, so when we go back to the time domain we need to remember that the frequency buffer is symmetric. Maybe we just punt and make the user use the correct `irfft`, etc, but it would be nice to use the `convert` infrastructure to convert between domains.

### Interpolation

Currently for real-valued indices like time we are just rounding to the nearest sample index, but often you'll want an interpolated value. How does the user specify what type of interpolation they want? One idea would be to allow an interpolation type symbol in the indexing, like `x[1.25s, :cubic]`, but that seems a little weird.

### Relative vs. Absolute indexing

When we take a slice of a SampleBuf (e.g. take the span from 1s to 3s of a 10s audio buffer), what is the indexing domain of the result? Specifically, is it 1s-3s, or is it 0s-2s? For time-domain signals I can see wanting indexing relative to the beginning of the buffer, bug in frequency-domain buffers it seems you usually want to keep the frequency information. Keeping track of the time information could also be useful if you split out a signal for processing and then want to re-combine things at the end.
