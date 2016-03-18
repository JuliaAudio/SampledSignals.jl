# SampleTypes

[![Build Status](https://travis-ci.org/JuliaAudio/SampleTypes.jl.svg?branch=master)] (https://travis-ci.org/JuliaAudio/SampleTypes.jl)
[![codecov.io] (http://codecov.io/github/JuliaAudio/SampleTypes.jl/coverage.svg?branch=master)] (http://codecov.io/github/JuliaAudio/SampleTypes.jl?branch=master)

SampleTypes is a collection of types intended to be used on multichannel sampled signals like audio or radio data, EEG signals, etc., to provide better interoperability between packages that read data from files or streams, DSP packages, and output and display packages.

SampleTypes provides several types to stream and store sampled data: `SampleBuf`, `SampleSource`, `SampleSink` and also an `Interval` type that can be used to represent contiguous ranges using a convenient `a..b` syntax, this feature is copied mostly from the [AxisArrays](https://github.com/mbauman/AxisArrays.jl) package, which also inspired much of the implementation of this package.

We also use the [SIUnits](https://github.com/keno/SIUnits.jl) package to enable indexing using real-world units like seconds or hertz. `SampleTypes` re-exports the relevant `SIUnits` units (`ns`, `ms`, `µs`, `s`, `Hz`, `kHz`, `MHz`, `GHz`, `THz`) so you don't need to import `SIUnits` explicitly.

## Types

### SampleBuf

`SampleBuf` is an abstract type representing multichannel, regularly-sampled data, providing handy indexing operations. It subtypes AbstractArray and should be drop-in compatible with raw arrays, with the exception that indexing a row (a single frame of multiple channels) will result in a 1xN result instead of a 1D Vector, which is the Array behavior as of 0.5. The two main advantages of SampleBufs are they are sample-rate aware and that they support indexing with real-world units like seconds or hertz (depending on the domain). To create a custom subtype of `SampleBuf` you only need to define `Base.similar` so that the result of indexing operations and arithmetic will be wrapped correctly and `SampleTypes.toindex` which defines how a unit quantity should be mapped to an index. The rest of the methods are defined on `SampleBuf` so they should Just Work.

SampleTypes also implements two concrete `SampleBuf` subtypes for commonly-used domains:

* `TimeSampleBuf`, which supports indexing in seconds
* `FrequencySampleBuf` which supports indexing in hertz

### SampleSource

A source of samples, which might for instance represent a microphone input. The `read` method just gives you a single frame (an 1xN N-channel `TimeSampleBuf`), but you can also read an integer number of samples or an amount of time given in seconds. This package includes the `DummySampleSource` concrete type that is useful for testing the stream interface.

### SampleSink

A sink for samples to be written to, for instance representing your laptop speakers. The main method used here is `write` which writes a `SampleBuf` to a `SampleSink`. This package includes the `DummySampleSink` concrete type that is useful for testing the stream interface.

## Stream Read/Write Semantics

SampleTypes tries to keep the semantics of reading and writing simple and consistent. If a read or write is attempted and there's not enough space or samples available (but the stream is still open), the operation will block the task until it can proceed. If the stream is closed, you can always check the return value of the operation for a partially-completed read or write.

Rather than specifying read and write durations in terms of frames, you can also specify in seconds. In this case `read!` and `write` will return seconds as well. If the operation completes fully, the returned duration will exactly match the given duration, so you can still check for equality.

`read!(source, buf)` reads from `source` and places the data in `buf`. It returns the number of frames that were read. If the number returned is less than the length of `buf`, you know that `source` was closed before the read was complete.

`read(source, n)` reads `n` frames from the source and returns a new buffer filled with their contents. If the length of the returned buffer is shorter than `n` then you know that `source` was closed before the read was complete.

`write(sink, buf)` writes the contents of `buf` into `sink`, and returns the number of frames that were written. If fewer frames were written than the length of `buf`, you know that `sink` was closed before the write was complete.

`write(sink, source)` reads from `source` and writes to `sink` a block at a time, and returns the number of frames written to `sink`.

`write(sink, source, n)` reads from `source` and writes to `sink` a block at a time, and returns the number of frames written to `sink`. If both the streams stay open it will return after writing `n` frames.

`read!(source, sink)` reads from `source` and writes to `sink` a block at a time, and returns the number of frames read from `source`. This method is not currently implemented.

Note that when connecting `source`s to `sink`s, the only difference between `read!` and `write` is the return value. If the sampling rates match then the value returned should be the same in both cases, but will be different in the case of a samplerate conversion.

## Defining Custom Sink/Source types

Say you have a library that moves audio over a network, or interfaces with some software-defined radio hardware. You should be able to easily tap into the SampleTypes infrastructure by doing the following:

1. subtype `SampleSink{N, SR, T}` and `SampleSource{N, SR, T}`
2. implement `Base.read!` and `Base.write` for your type, with channel count, sample rate, and type matching between your stream type and the buffer type.

For example, to define `MySink` and `MySource` types, you would define the following methods:

```julia
Base.write{N, SR, T}(sink::MySink{N, SR, T}, buf::TimeSampleBuf{N, SR, T})
Base.read!{N, SR, T}(src::MySource{N, SR, T}, buf::TimeSampleBuf{N, SR, T})
```

Other methods, such as the non-modifying `read`, sample-rate converting versions, and time-based indexing are all handled by SampleTypes. You can see the implementation of `DummySampleSink` and `DummySampleSource` in [DummySampleStream.jl](src/DummySampleStream.jl) for a more complete example.

## Connecting Streams

In addition to reading and writing buffers to streams, you can also set up direct stream-to-stream connections using the `write` function. For instance, if you have the streams `in` and `out`, you can connect them with `write(out, in)`. This will block the current task until the `in` stream ends. The implementation just reads a block at a time from `in` and writes the received data to `out`. You can set the blocksize with an optional third argument, e.g. `write(out, in, 1024)` will read blocks of 1024 frames at a time. The default blocksize is 4096.

## Conversions (TODO)

Sometimes you have a source of data (a `SampleBuf` or `SampleSource`) that is not in the same format as the stream you want to write to. For instance, you may have a audio file recorded at 44.1kHz and want to play to your soundcard configured for 48kHz (samplerate conversion). Or you want to play a mono microphone signal through your stereo soundcard (channel conversion). Or you generated a buffer of floating point values that you want to write to a 16-bit integer WAVE file (format conversion). SampleTypes handles these conversions transparently.

SampleTypes uses SampleSourceWrapper and SampleSinkWrapper types to implement this conversion. Normally these wrappers are created automatically when you attempt an operation that needs conversion, but you can also create them explictly. For instance, if you have a sink `sink` that is operating at 48kHz (say a soundcard output), and a source `source`, the code `write(sink, source)` is equivalent to:

```julia
wrapper = SampleSinkWrapper(sink, nchannels(sink), 48000, eltype(sink))
write(wrapper, source)
```

### Samplerate Conversion

Currently SampleTypes handles resampling with simple linear interpolation. In the future we will likely implement other resampling methods.

### Channel Conversion

### Format Conversion

## Sticky Design Issues

There are a number of issues that I'm still in the process of figuring out:

### Complexity and Symmetry

A real-valued time-domain buffer becomes a symmetric complex frequency-domain buffer, so when we go back to the time domain we need to remember that the frequency buffer is symmetric. Maybe we just punt and make the user use the correct `irfft`, etc, but it would be nice to use the `convert` infrastructure to convert between domains.

### Interpolation

Currently for real-valued indices like time we are just rounding to the nearest sample index, but often you'll want an interpolated value. How does the user specify what type of interpolation they want? One idea would be to allow an interpolation type symbol in the indexing, like `x[1.25s, :cubic]`, but that seems a little weird.

### Relative vs. Absolute indexing

When we take a slice of a SampleBuf (e.g. take the span from 1s to 3s of a 10s audio buffer), what is the indexing domain of the result? Specifically, is it 1s-3s, or is it 0s-2s? For time-domain signals I can see wanting indexing relative to the beginning of the buffer, but in frequency-domain buffers it seems you usually want to keep the frequency information. Keeping track of the time information could also be useful if you split out a signal for processing and then want to re-combine things at the end.

### Views/SubArrays

We don't currently implement `sub(buf::SampleBuf, A...)` for view-based indexing, so if you use `sub` you just get back a regular SubArray of the data, and lose the channel / samplerate data. Every time you index with a range you get back a new copy of the data, which is often not great for efficiency. Should we create a `SubSampleBuf` type (and an `AbstractSampleBuf` to contain both `SubSampleBuf` and `SampleBuf`)?

### Handling conversions

Because we have the sample type, channel count and sampling rate as type parameters, we can talk about samplerate conversions, channel up/down-mixing, etc. in the language of type conversions. For instance, we might want to define `convert(::Type{SampleBuf{N, SR1, T}}, buf::SampleBuf{N, SR2, T})` to resample the given buffer to the new sampling rate. We could also consider a `resample` function, e.g. `resample(buf::SampleBuf, rate)`, but this would not be type-stable because the type of the result buffer would depend on the value of the `rate` parameter.

There are several use cases where conversions come up:

* writing a buffer to a stream with a different rate, channel count, or eltype
* writing one stream to another stream
* using `read!` on a stream and giving a receive buffer with different parameters

One issue to consider is that samplerate conversion requires some state, so it's not a great idea to just implement conversion when writing a buffer to a mis-matched stream. You want something that can persist the state across writes.

#### Possible Architectures

1. Create `UpMixSink`, `DownMixSink`, `ResampleSink`, `FormatConvertSink` types, which are wrappers around another `*Sink` type. For example, you might have a `SampleSink{2, 44100, Float32}` wrapped in a `ResampleSink` that's a `SampleSink{2, 48000, Float32}`. When you write a buffer to the `ResampleSink` with a sample rate of 48000, it gets resampled to 44100. It's also able to maintain state across writes so the resampling is correct. We also might want to create converting `Source` wrappers as well, in case we want to convert on `read`s. Calling `convert` on a source or sink would wrap it in a converter object and return the wrapper, or possibly a set of nested converter objects. Calling `convert` on a buffer would give you a new, converted, buffer.
2. Create `SinkWrapper` and `SourceWrapper` types that handle all the necessary conversion. This might be more efficient as we could do multiple conversions at once instead of nested wrappers.
2. Define `read!` and `write` for stream-to-stream that just keep the state in the method during the operation.

```julia
sink = SomeSinkType() # <: SampleSink{2, 44100, Float32}
source = SomeSourceType() # <: SampleSource{2, 48000, Float32}

# the following should block the task until the source is over (or closed). For
# this use case I think either architecture would work:
#  1. wrap the source in a converter and call write
#  2. wrap the sink in a converter and call write
#  3. create a temp buffer and a while loop that reads from the source,
#     converts, and writes to the sink
write(sink, source)

snd = load("somefile.wav") # <: SampleBuf{2, 96000, Float32}
# if it's just this one write of an isolated buffer, we don't really care about
# continuity so we could:
#  1. convert the whole buffer and then write it to the sink
#  2. convert the buffer in pieces and write each to the sink sequentially
#  3. wrap the sink in a converter object and write the buffer to it
#  4. wrap the buffer in a converter Source and write it to the sink
write(sink, snd)

# this is a simple example of processing a stream before passing it along (in
# this case just scaling it by 2). In this example we'd want to make sure that
# the samplerate conversion would maintain state across writes, which doesn't
# seem possible with any of our architectures above.
blocksize = 1024
while true
    buf = SampleBuf(Float32, 48000, blocksize, 2)
    n = read!(source, buf)
    for i in 1:n
        buf[i] *= 2
    end
    write(sink, buf[1:n]) # currently this indexing will allocate and copy :(
    if n < blocksize
        break
    end
end

# perhaps it needs to be:

blocksize = 1024
# there appears to be precedent for `convert`ing to an abstract type, e.g.
# `convert(AbstractFloat, 1/3)`
wrapper = convert(SampleSource{2, 44100, Float32}, source)
# or
wrapper = SinkWrapper{2, 44100, Float32}(source)
# or
wrapper = resample(source, 44100) # not type stable
while true
    buf = SampleBuf(Float32, 44100, blocksize, 2)
    n = read!(wrapper, buf)
    for i in 1:n
        buf[i] *= 2
    end
    write(sink, buf[1:n]) # currently this indexing will allocate and copy :(
    if n < blocksize
        break
    end
end
