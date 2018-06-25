using SampledSignals
using Compat.Test
using FixedPointNumbers
using WAV
using Gumbo

function parsehtmldisplay(buf)
    outputbuf = IOBuffer()
    display(TextDisplay(outputbuf), "text/html", buf)
    fragment = String(take!(outputbuf))

    fullhtml = """
    <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN"
        "http://www.w3.org/TR/html4/strict.dtd">
    <html lang="en">
      <body>
        $fragment
      </body>
    </html>"""

    doc = parsehtml(fullhtml, strict=true)
    body = doc.root[2]
    @assert tag(body) == :body

    # return the body of the parsed HTML doc
    body
end

# looks for a button child with a span child that has the given class, which is
# how font-awesome displays icons
function hasiconbtn(doc, css_class)
    for maybebutton in children(doc)
        if tag(maybebutton) == :button
            for maybespan in children(maybebutton)
                if tag(maybespan) == :span
                    classes = split(getattr(maybespan, "class"))
                    css_class in classes && return true
                end
            end
        end
    end
    return false
end

@testset "WAVDisplay Tests" begin
    @testset "SampleBuf display Generates valid HTML" begin
        buf = SampleBuf(rand(16, 2), 48000)
        parsehtmldisplay(buf)
    end

    @testset "SampleBuf display has the right buttons" begin
        buf = SampleBuf(rand(16, 2), 48000)
        output = parsehtmldisplay(buf)
        @test hasiconbtn(output, "fa-step-backward")
        @test hasiconbtn(output, "fa-step-forward")
        @test hasiconbtn(output, "fa-play")
        @test hasiconbtn(output, "fa-stop")
    end

    # @testset "SpectrumBuf display Generates valid HTML" begin
    #     buf = SpectrumBuf(rand(16, 2), 48000)
    #     parsehtmldisplay(buf)
    # end

    # @testset "SpectrumBuf display doesn't show buttons" begin
    #     buf = SpectrumBuf(rand(16, 2), 48000)
    #     output = parsehtmldisplay(buf)
    #     @test !hasiconbtn(output, "fa-step-backward")
    #     @test !hasiconbtn(output, "fa-step-forward")
    #     @test !hasiconbtn(output, "fa-play")
    #     @test !hasiconbtn(output, "fa-stop")
    # end

    @testset "wavwrite Generates valid WAV file with raw Int16" begin
        buf = SampleBuf(rand(Int16, 4, 2), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        samples, fs, nbits, opt = wavread(IOBuffer(take!(io)), format="native")
        @test samples == buf
        @test fs == 48000
        @test nbits == 16
    end

    @testset "wavwrite Generates valid WAV file with raw 16-bit Fixed-point" begin
        buf = SampleBuf(reinterpret.(Fixed{Int16, 15}, rand(Int16, 4, 2)), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        samples, fs, nbits, opt = wavread(IOBuffer(take!(io)), format="native")
        @test samples == reinterpret.(Array(buf))
        @test fs == 48000
        @test nbits == 16
    end

    @testset "wavwrite converts float values to 16-bit int wav" begin
        buf = SampleBuf(rand(4, 2), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        samples, fs, nbits, opt = wavread(IOBuffer(take!(io)), format="native")
        @test samples == map(reinterpret, Array{PCM16Sample}(buf))
        @test fs == 48000
        @test nbits == 16
    end

    @testset "wavwrite converts Int32 values to 16-bit int wav" begin
        data = rand(4, 2)*0.9
        buf = SampleBuf(Fixed{Int32, 31}.(data), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        samples, fs, nbits, opt = wavread(IOBuffer(take!(io)), format="native")
        # convert 32-bit int buf to float, then to 16-bit, for testing
        @test samples == reinterpret.(Array{PCM16Sample}(Float32.(buf)))
        @test fs == 48000
        @test nbits == 16
    end

    # this is used to display spectrum magnitudes using the same infrastructure
    # as displaying/playing time-domain buffers
    # @testset "wavwrite converts complex float values to 16-bit int wav" begin
    #     complexbuf = SpectrumBuf(rand(Complex{Float32}, 16, 2), 48000)
    #     floatbuf = map(abs, complexbuf)
    #     complexio = IOBuffer()
    #     floatio = IOBuffer()
    #     SampledSignals.wavwrite(complexio, complexbuf)
    #     SampledSignals.wavwrite(floatio, floatbuf)
    #     complexsamples, fs, nbits, opt = wavread(IOBuffer(take!(complexio)), format="native")
    #     floatsamples, _, _, _ = wavread(IOBuffer(take!(floatio)), format="native")
    #     @test isapprox(complexsamples, floatsamples)
    #     @test fs == 48000
    #     @test nbits == 16
    # end
end
