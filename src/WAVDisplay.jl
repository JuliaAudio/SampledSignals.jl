# the .wav code is largely cut/pasted and cut down from @dancasimiro's
# WAV.jl package. Rather than full WAV support here we just want to support
# enough for simple HTML display of SampleBufs

# need to specify that T <: Number to avoid a method ambiguity with AbstractArray{Method} on 0.4
function show(io::IO, ::MIME"text/html", buf::SampleBuf{T, N}) where {T <: Number, N}
    tempio = IOBuffer()
    wavwrite(tempio, buf)
    data = base64encode(take!(tempio))
    if isa(buf, SampleBuf) && eltype(buf) <: Real
        println(io, """
        <audio controls>
            <source src="data:audio/wav;base64,$data" />
        </audio>""")
    else
        show(io, MIME"text/plain"(), buf)
    end
end

TreeViews.hastreeview(::SampleBuf) = true
TreeViews.numberofnodes(::SampleBuf) = 0
function TreeViews.treelabel(io::IO, buf::SampleBuf, ::MIME"text/html")
    show(io, MIME"text/html"(), buf)
end

# Required WAV Chunk; The format chunk describes how the waveform data is stored
struct WAVFormat
    audioformat::UInt16
    nchannels::UInt16
    sample_rate::UInt32
    bytes_per_second::UInt32 # average bytes per second
    block_align::UInt16
    nbits::UInt16
end

# we'll only ever write these formats
const WAVE_FORMAT_PCM = 0x0001
const SAMPLE_TYPE = PCM16Sample

# floating-point and 16-bit fixed point buffer display works, but Int32 is
# broken, so for now we convert to Float32 first. This hack should go away once
# we switch over to just using WAV.jl
function wavwrite(io::IO, buf::SampleBuf)
    wavwrite(io, Float32.(buf))
end

# we always write 16-bit PCM wav data, because that's what Firefox understands
function wavwrite(io::IO, buf::SampleBuf{<:Union{Int16, SAMPLE_TYPE, AbstractFloat}, N}) where N
    nbits = 16
    nchans = nchannels(buf)
    blockalign = 2 * nchans
    sr = round(UInt32, float(samplerate(buf)))
    bps = sr * blockalign
    datalength::UInt32 = nframes(buf) * blockalign

    write_header(io, datalength)
    write_format(io, WAVFormat(WAVE_FORMAT_PCM, nchans, sr, bps, blockalign, nbits))

    # write the data subchunk header
    write(io, b"data")
    write_le(io, datalength) # UInt32
    # write_data(io, fmt, buf.data')
    for f in 1:nframes(buf), ch in 1:nchannels(buf)
        write_le(io, buf[f, ch])
    end
end


write_le(stream::IO, val::Complex) = write_le(stream, abs(val))
write_le(stream::IO, val::AbstractFloat) = write_le(stream,
    SAMPLE_TYPE(clamp(val, typemin(SAMPLE_TYPE), typemax(SAMPLE_TYPE))))
write_le(stream::IO, val::FixedPoint) = write_le(stream, reinterpret(val))
write_le(stream::IO, value) = write(stream, htol(value))

function write_header(io::IO, datalength)
    write(io, b"RIFF") # RIFF header
    write_le(io, UInt32(datalength+36)) # chunk_size
    write(io, b"WAVE")
end

function write_format(io::IO, fmt::WAVFormat)
    len = 16 # 16 is size of base format chunk
    # write the fmt subchunk header
    write(io, b"fmt ")
    write_le(io, UInt32(len)) # subchunk length

    write_le(io, fmt.audioformat) # audio format (UInt16)
    write_le(io, fmt.nchannels) # number of channels (UInt16)
    write_le(io, fmt.sample_rate) # sample rate (UInt32)
    write_le(io, fmt.bytes_per_second) # byte rate (UInt32)
    write_le(io, fmt.block_align) # byte align (UInt16)
    write_le(io, fmt.nbits) # number of bits per sample (UInt16)
end
