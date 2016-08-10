# this code is largely cut/pasted and cut down from @dancasimiro's
# WAV.jl package. Rather than full WAV support here we just want to support
# enough for simple HTML display of SampleBufs

@compat function show(io::IO, ::MIME"text/html", buf::SampleBuf)
    tempio = IOBuffer()
    wavwrite(tempio, buf)
    data = base64encode(takebuf_array(tempio))
    markup = """<audio controls="controls" {autoplay}>
                <source src="data:audio/wav;base64,$data" type="audio/wav" />
                Your browser does not support the audio element.
                </audio>"""
    print(io, markup)
end

# Required WAV Chunk; The format chunk describes how the waveform data is stored
immutable WAVFormat
    audioformat::UInt16
    nchannels::UInt16
    sample_rate::UInt32
    bytes_per_second::UInt32 # average bytes per second
    block_align::UInt16
    nbits::UInt16
end

# we'll only ever write these formats
const WAVE_FORMAT_PCM        = 0x0001 # PCM
const WAVE_FORMAT_IEEE_FLOAT = 0x0003 # IEEE float

function wavwrite(io::IO, buf::SampleBuf)
    nbits = get_nbits(buf)
    nchans = nchannels(buf)
    blockalign = nbits / 8 * nchans
    sr = round(Uint32, float(samplerate(buf)))
    bps = sr * blockalign
    datalength::UInt32 = nframes(buf) * blockalign

    write_header(io, datalength)
    write_format(io, WAVFormat(get_format(buf), nchans, sr, bps, blockalign, nbits))

    # write the data subchunk header
    write(io, b"data")
    write_le(io, datalength) # UInt32
    # write_data(io, fmt, buf.data')
    for f in 1:nframes(buf), ch in 1:nchannels(buf)
        write_le(io, buf[f, ch])
    end
end

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

get_nbits(::AbstractArray{UInt8}) = 8
get_nbits(::AbstractArray{Int16}) = 16
get_nbits(::Any) = 24
get_nbits(::AbstractArray{Float32}) = 32
get_nbits(::AbstractArray{Float64}) = 64

get_format{T <: Integer}(::AbstractArray{T}) = WAVE_FORMAT_PCM
get_format{T <: AbstractFloat}(::AbstractArray{T}) = WAVE_FORMAT_IEEE_FLOAT
