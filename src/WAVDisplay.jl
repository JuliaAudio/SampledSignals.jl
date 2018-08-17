# the .wav code is largely cut/pasted and cut down from @dancasimiro's
# WAV.jl package. Rather than full WAV support here we just want to support
# enough for simple HTML display of SampleBufs

# notebook init code heavily inspired by PlotlyJS - thanks @sglyon!
function embed_javascript()
    js_path = joinpath(dirname(dirname(@__FILE__)), "deps", "wavesurfer.min.js")
    js_text = open(js_path) do io
        read(io, String)
    end
    # the javascript file contains the code to add itself to the require module
    # cache under the name 'wavesurfer'
    display("text/html", """
    <script charset="utf-8" type='text/javascript'>
    $js_text
    console.log("SampledSignals.jl: wavesurfer library loaded")
    </script>
    """)
end

function show(io::IO, ::MIME"text/html", buf::SampleBuf)
    tempio = IOBuffer()
    wavwrite(tempio, buf)
    data = base64encode(take!(tempio))
    # we want the divID to start with a letter
    divid = string("a", randstring(10))
    # include an error message that will get cleared if javascript loads correctly
    # they won't be able to re-run this cell without importing SampledSignals,
    # which will run the initialization code above. I can't think of a way to
    # get in the state where the javascript isn't initialized but the module is
    # loaded, but if it comes up we'll want to add an instruction to run
    # `SampledSignals.embed_javascript()`.
    println(io, """
        <div id=$divid>
            <h4>SampleBuf display requires javascript</h4>
            <p>To enable for the whole notebook select "Trust Notebook" from the
            "File" menu. You can also trust this cell by re-running it. You may
            also need to re-run `using SampledSignals` if the module is not yet
            loaded in the Julia kernel, or `SampledSignals.embed_javascript()`
            if the Julia module is loaded but the javascript isn't initialized.</p>
        </div>""")
    # only show playback controls for real-valued SampleBufs. We also initialize
    # them hidden and they get displayed if javascript is enabled.
    if isa(buf, SampleBuf) && eltype(buf) <: Real
        println(io, """
        <button id=$divid-skipback class="btn" style="display:none">
            <span class="fa fa-step-backward"></span>
        </button>
        <button id=$divid-playpause class="btn" style="display:none">
            <span class="fa fa-play"></span>
        </button>
        <button id=$divid-stop class="btn" style="display:none">
            <span class="fa fa-stop"></span>
        </button>
        <button id=$divid-skipahead class="btn" style="display:none">
            <span class="fa fa-step-forward"></span>
        </button>""")
    end
    println(io, """
    <script type="text/javascript">
        require(["wavesurfer"], function(wavesurfer) {
            \$("#$divid").empty();
            var waveform = wavesurfer.create({
                container: '#$divid',
                splitChannels: true,
                scrollParent: true,
                height: 40
            });
            var base64 = "$data";
            var binary_string = window.atob(base64);
            var len = binary_string.length;
            var bytes = new Uint8Array(len);
            for (var i = 0; i < len; i++) {
                bytes[i] = binary_string.charCodeAt(i);
            }
            waveform.loadArrayBuffer(bytes.buffer);
            \$("#$divid-skipback").show();
            \$("#$divid-skipahead").show();
            \$("#$divid-playpause").show();
            \$("#$divid-stop").show();

            \$("#$divid-skipback").click(function(event) {
                waveform.skip(-3);
            });
            \$("#$divid-skipahead").click(function(event) {
                waveform.skip(3);
            });
            \$("#$divid-playpause").click(function(event) {
                var el = \$("#$divid-playpause span")
                if(waveform.isPlaying()) {
                    waveform.pause();
                    el.removeClass("fa-pause");
                    el.addClass("fa-play");
                }
                else {
                    waveform.play();
                    el.removeClass("fa-play");
                    el.addClass("fa-pause");
                }
            });
            \$("#$divid-stop").click(function(event) {
                waveform.stop();
                var el = \$("#$divid-playpause span")
                el.removeClass("fa-pause");
                el.addClass("fa-play");
            });
            waveform.on('finish', function() {
                var el = \$("#$divid-playpause span")
                el.removeClass("fa-pause");
                el.addClass("fa-play");
            })
        });
    </script>
    """)
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
const NativeBitrate = PCM16Sample

# floating-point and 16-bit fixed point buffer display works, but Int32 is
# broken, so for now we convert to Float32 first. This hack should go away once
# we switch over to just using WAV.jl
const ValidBitrate = Union{Int16, NativeBitrate, AbstractFloat}
wavwrite(io::IO, buf::SampleBuf) = wavwrite(io, Float32.(buf))
function wavwrite(io::IO, buf::SampleBuf{<:Any,<:Any,<:ValidBitrate, N}) where N
    nbits = 16
    nchans = nchannels(buf)
    blockalign = 2 * nchans
    sr = round(UInt32, float(samplerate(buf)))
    bps = sr * blockalign
    datalength::UInt32 = nframes(buf) * blockalign

    write_header(io, datalength)
    write_format(io, WAVFormat(WAVE_FORMAT_PCM, nchans, sr, bps,
                               blockalign, nbits))

    # write the data subchunk header
    write(io, b"data")
    write_le(io, datalength) # UInt32
    # write_data(io, fmt, buf.data')
    @inbounds for f in 1:nframes(buf), ch in 1:nchannels(buf)
        write_le(io, buf[f, ch])
    end
end

write_le(stream::IO, val::Complex) = write_le(stream, abs(val))
write_le(stream::IO, val::AbstractFloat) = write_le(stream,
    NativeBitrate(clamp(val, typemin(NativeBitrate), typemax(NativeBitrate))))
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
