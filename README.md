# SampleTypes

[![Build Status](https://travis-ci.org/ssfrr/SampleTypes.jl.svg?branch=master)] (https://travis-ci.org/ssfrr/SampleTypes.jl) [![codecov.io] (http://codecov.io/github/ssfrr/SampleTypes.jl/coverage.svg?branch=master)] (http://codecov.io/github/ssfrr/SampleTypes.jl?branch=master)

**Note - this is very much a work in progress and not ready for public use**

SampleTypes is a collection of types intended to be used on multichannel sampled signals like audio or radio data, to provide better interoperability between packages that read data from files or streams, DSP packages, and output and display packages.

SampleTypes provides several types to stream and store sampled data: `AbstractSampleBuf`, `TimeSampleBuf`, `FrequencySampleBuf`, `SampleSource`, `SampleSink` and also an `Interval` type that can be used to represent contiguous ranges using a convenient `a..b` syntax, this feature is copied mostly from the [AxisArrays](https://github.com/mbauman/AxisArrays.jl) package, which also inspired much of the implementation of this package.

We also use the [SIUnits](https://github.com/keno/SIUnits.jl) package to enable indexing using real-world units like seconds or hertz. `SampleTypes` re-exports the relevant `SIUnits` units (`ns`, `ms`, `µs`, `s`, `Hz`, `kHz`, `MHz`, `GHz`, `THz`) so you don't need to import `SIUnits` explicitly.

## Examples

These examples use the [LibSndFile](https://github.com/ssfrr/LibSndFile.jl) library which enables reading and writing from a variety of audio file formats using `SampleTypes` types and also integrates with the `FileIO` `load` and `save` API.

**Read ogg file, write first 1024 samples of the first channel to new wav file**
```julia
x = load("myfile.ogg")
save("myfile_short.wav", x[1:1024])
```

**Read file, write the first second of all channels to a new file**
```julia
x = load("myfile.ogg")
save("myfile_short.wav", x[0s..1s, :])
```

**Read stereo file, write mono mix**
```julia
x = load("myfile.wav")
save("myfile_mono.wav", x[:, 1] + x[:, 2])
```

**Plot an the left channel**
```julia
x = load("myfile.wav")
plot(x[:, 1]) # plots with samples on the x axis
plot(domain(x), x[:, 1]) # plots with time on the x axis
```

**Plot the frequency response of the left channel**
```julia
x = load("myfile.wav")
f = fft(x) # returns a FrequencySampleBuf
plot(domain(x), x[:, 1]) # plots with frequency on the x axis
```

**Load a long file as a stream and plot the left channel from 2s to 3s**
```julia
s = load("myfile.ogg", streaming=true)
x = read(s, 4s)[2s..3s, 1]
plot(domain(x), x)
```

## Types

### AbstractSampleBuf

`AbstractSampleBuf` is an abstract type representing multichannel, regularly-sampled data, providing handy indexing operations. It subtypes AbstractArray and should be drop-in compatible with raw arrays, with the exception that indexing with a linear range will result in a 2D Nx1 result instead of a 1D Vector. The two main advantages of SampleBufs are they are sample-rate aware and that they support indexing with real-world units like seconds or hertz (depending on the domain). To create a custom subtype of `AbstractSampleBuf` you only need to define `Base.similar` so that the result of indexing operations and arithmetic will be wrapped correctly and `SampleTypes.toindex` which defines how a unit quantity should be mapped to an index. The rest of the methods are defined on `AbstractSampleBuf` so they should Just Work.

SampleTypes also implements two concrete `AbstractSampleBuf` subtypes for commonly-used domains:

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
