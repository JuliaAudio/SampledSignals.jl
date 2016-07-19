# SampledSignals

[![Build Status](https://travis-ci.org/JuliaAudio/SampledSignals.jl.svg?branch=master)] (https://travis-ci.org/JuliaAudio/SampledSignals.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/qioy8vjpwg51s77p?svg=true)](https://ci.appveyor.com/project/ssfrr/sampledsignals-jl)
[![codecov.io] (http://codecov.io/github/JuliaAudio/SampledSignals.jl/coverage.svg?branch=master)] (http://codecov.io/github/JuliaAudio/SampledSignals.jl?branch=master)

SampledSignals is a collection of types intended to be used on multichannel sampled signals like audio or radio data, EEG signals, etc., to provide better interoperability between packages that read data from files or streams, DSP packages, and output and display packages.

SampledSignals provides several types to stream and store sampled data: `SampleBuf`, `SampleSource`, `SampleSink` and also an `Interval` type that can be used to represent contiguous ranges using a convenient `a..b` syntax, this feature is copied mostly from the [AxisArrays](https://github.com/mbauman/AxisArrays.jl) package, which also inspired much of the implementation of this package.

We also use the [SIUnits](https://github.com/keno/SIUnits.jl) package to enable indexing using real-world units like seconds or hertz. `SampledSignals` re-exports the relevant `SIUnits` units (`ns`, `ms`, `µs`, `s`, `Hz`, `kHz`, `MHz`, `GHz`, `THz`) so you don't need to import `SIUnits` explicitly.

Because these buffer and stream types are sample-rate and channel-count aware, this package can automatically handle situations like writing a mono source into a stereo buffer, or resampling to match sample rates. This greatly simplifies the process of writing new streaming sample back-ends, because you only need to implement a small number of fundamental read/write operations, and SampledSignals will handle the plumbing.

## Types

### SampleBuf

A `SampleBuf` represents multichannel, regularly-sampled data, providing handy indexing operations. It subtypes AbstractArray and should be drop-in compatible with raw arrays, with the exception that indexing a row (a single frame of multiple channels) will result in a 1xN result (a 1-frame multichannel buffer) instead of a 1D Vector, which is the Array behavior as of 0.5. The two main advantages of SampleBufs are they are sample-rate aware and that they support indexing with real-world units like seconds or hertz (depending on the domain).

### SampleSource

`SampleSource` is an abstract type representing a source of samples, which might for instance represent a microphone input. The `read` method just gives you a single frame (an 1xN N-channel `SampleBuf`), but you can also read an integer number of samples or an amount of time given in seconds. This package includes the `DummySampleSource` concrete type that is useful for testing the stream interface.

### SampleSink

`SampleSink` is an abstract type representing a sink for samples to be written to, for instance representing your laptop speakers. The main method used here is `write` which writes a `SampleBuf` to a `SampleSink`. This package includes the `DummySampleSink` concrete type that is useful for testing the stream interface.

## Stream Read/Write Semantics

SampledSignals tries to keep the semantics of reading and writing simple and consistent. If a read or write is attempted and there's not enough space or samples available (but the stream is still open), the operation will block the task until it can proceed. If the stream is closed, you can always check the return value of the operation for a partially-completed read or write.

Rather than specifying read and write durations in terms of frames, you can also specify in seconds. In this case `read!` and `write` will return seconds as well. If the operation completes fully, the returned duration will exactly match the given duration, so you can still check for equality.

`read!(source, buf)` reads from `source` and places the data in `buf`. It returns the number of frames that were read. If the number returned is less than the length of `buf`, you know that `source` was closed before the read was complete.

`read(source, n)` reads `n` frames from the source and returns a new buffer filled with their contents. If the length of the returned buffer is shorter than `n` then you know that `source` was closed before the read was complete.

`write(sink, buf)` writes the contents of `buf` into `sink`, and returns the number of frames that were written. If fewer frames were written than the length of `buf`, you know that `sink` was closed before the write was complete.

`write(sink, source)` reads from `source` and writes to `sink` a block at a time, and returns the number of frames written to `sink`.

`write(sink, source, n)` reads from `source` and writes to `sink` a block at a time, and returns the number of frames written to `sink`. If both the streams stay open it will return after writing `n` frames.

`read!(source, sink)` reads from `source` and writes to `sink` a block at a time, and returns the number of frames read from `source`. This method is not currently implemented.

Note that when connecting `source`s to `sink`s, the only difference between `read!` and `write` is the return value. If the sampling rates match then the value returned should be the same in both cases, but will be different in the case of a samplerate conversion.

## Plotting Support

SampledSignals adds the `domain` function for `SampleBuf`s, which gives you the domain in real-world units at the buffer's sampling rate. This is especially useful for plotting because you can simply run `plot(x=domain(buf), y=buf)` and see your x axis in seconds. This also works for frequency-domain buffers, so you can do:

```julia
spec = fft(buf)
plot(x=domain(spec), y=abs(spec))
```

and see the magnitude spectrum plotted against actual frequencies.

## REPL Display

When displaying a buffer at the REPL, SampledSignals shows the length, channel count, sample rate, and duration. It also shows a coarse audio waveform, which
shows the signal amplitude in dB.

```julia
julia> [buf[1:44100] buf[44100:88199]]
44100-frame, 2-channel SampleBuf{FixedPointNumbers.Fixed{Int16,15}, 2, SIUnits.SIQuantity{Int64,0,0,-1,0,0,0,0,0,0}}
1.0 s at 44100 s⁻¹
▁▁▁▁▁▁▁▁▂▁▁▁▃▂▅▅▅▅▅▅▅▅▆▅▅▅▄▃▃▄▅▅▄▄▄▃▄▃▂▅▅▅▄▃▁▂▄▄▄▄▄▄▄▄▅▅▅▅▅▄▃▂▄▅▅▅▅▅▅▅▅▅▅▅▅▄▃▂▄▄
▃▃▄▄▄▃▂▂▂▂▄▃▄▄▄▄▄▄▅▅▅▅▅▅▅▅▅▅▄▂▂▁▁▅▃▃▂▄▂▄▃▃▄▃▄▂▁▃▂▂▃▃▃▃▃▃▃▃▃▃▃▄▄▄▅▅▄▄▄▆▆▄▃▅▄▂▁▁▂▁
```

## Defining Custom Sink/Source types

Say you have a library that moves audio over a network, or interfaces with some software-defined radio hardware. You should be able to easily tap into the SampledSignals infrastructure by doing the following:

1. Subtype `SampleSink` or `SampleSource`
2. Implement `SampledSignals.unsafe_read!` (for sources) or `SampledSignals.unsafe_write` (for sinks), which can assume that the channel count, sample rate, and type match between your stream type and the buffer type.
3. Implement `SampledSignals.samplerate`, `SampledSignals.nchannels`, and `Base.eltype` for your type.

For example, to define a `MySource` type, you would implement:

```julia
SampledSignals.unsafe_read!(src::MySource, buf::SampleBuf)
SampledSignals.samplerate(source::MySource)
SampledSignals.nchannels(source::MySource)
Base.eltype(source::MySource)
```

Other methods, such as the non-modifying `read`, sample-rate converting versions, and time-based indexing are all handled by SampledSignals. You can see the implementation of `DummySampleSink` and `DummySampleSource` in [DummySampleStream.jl](src/DummySampleStream.jl) or the [JACKAudio.jl](https://github.com/JuliaAudio/JACKAudio.jl) package for more complete examples.

## Connecting Streams

In addition to reading and writing buffers to streams, you can also set up direct stream-to-stream connections using the `write` function. For instance, if you have a sink `in` and a source `out`, you can connect them with `write(out, in)`. This will block the current task until the `in` stream ends, but you can give an optional third argument in samples or seconds to write a limited amount. The implementation just reads a block at a time from `in` and writes the received data to `out`. You can set the blocksize with a keyword argument, e.g. `write(out, in, blocksize=1024)` will read blocks of 1024 frames at a time. The default blocksize is 4096.

## Conversions

Sometimes you have a source of data (a `SampleBuf` or `SampleSource`) that is not in the same format as the stream you want to write to. For instance, you may have a audio file recorded at 44.1kHz and want to play to your soundcard configured for 48kHz (samplerate conversion). Or you want to play a mono microphone signal through your stereo soundcard (channel conversion). Or you generated a buffer of floating point values that you want to write to a 16-bit integer WAVE file (format conversion). SampledSignals handles these conversions transparently.

SampledSignals uses several wrapper types to implement this conversion. Normally these wrappers are created automatically when you attempt an operation that needs conversion, but you can also create them explictly. For instance, if you have a sink `sink` that is operating at 48kHz (say a soundcard output), and a source `source` at 44.1kHz, the code `write(sink, source)` is equivalent to:

```julia
wrapper = ResampleSink(sink, 44.1kHz)
write(wrapper, source)
```

### Samplerate Conversion

The `ResampleSink` wrapper type wraps around a sink. Writing to this wrapper sink will resample the given data and pass it to the original sink. It maintains state between writes so that the interpolation is correct across the boundaries of multiple writes.

Currently `ResampleSink` handles resampling with simple linear interpolation and no lowpass filtering when downsampling. In the future we will likely implement other resampling methods.

### Channel Conversion

The `UpMixSink` and `DownMixSink` types wrap around a multi-channel or single-channel sink, respectively, so that you can write a mono signal to a stereo or multichannel output and it will be written to all channels, or you can write a multi-channel signal into a mono sink and it will be down-mixed.

### Format Conversion

Format conversion is handled automatically by Julia when we write data from one buffer type to another. There are several potential gotchas to consider. When dealing with integer samples, it's better to represent them with `Fixed` from [FixedPointNumbers.jl](https://github.com/JeffBezanson/FixedPointNumbers.jl). For example, 16-bit integer samples can be represented by `Fixed{Int16, 15}`. This way julia knows how to convert properly between fixed and floating-point values. One problem with this is that 16-bit fixed-point data can only represent values in the interval [-1.0, 0.99997], so if you have full-scale [-1.0, 1.0] floating point data, you will run into problems converting to fixed point values.

## Sticky Design Issues

There are a number of issues that I'm still in the process of figuring out:

### Interpolation

Currently for real-valued indices like time we are just rounding to the nearest sample index, but often you'll want an interpolated value. How does the user specify what type of interpolation they want? One idea would be to allow an interpolation type symbol in the indexing, like `x[1.25s, :cubic]`, but that seems a little weird.

### Relative vs. Absolute indexing

When we take a slice of a SampleBuf (e.g. take the span from 1s to 3s of a 10s audio buffer), what is the indexing domain of the result? Specifically, is it 1s-3s, or is it 0s-2s? For time-domain signals I can see wanting indexing relative to the beginning of the buffer, but in frequency-domain buffers it seems you usually want to keep the frequency information. Keeping track of the time information could also be useful if you split out a signal for processing and then want to re-combine things at the end.
