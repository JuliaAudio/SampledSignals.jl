function parsehtmldisplay(buf)
    outputbuf = IOBuffer()
    @compat show(outputbuf, MIME"text/html"(), buf)
    fragment = takebuf_string(outputbuf)

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

    @testset "wavwrite Generates valid WAV file" begin
        buf = SampleBuf(rand(Int16, 16, 2), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        samples, fs, nbits, opt = wavread(IOBuffer(takebuf_array(io)), format="native")
        @test samples == buf
        @test fs == 48000
        @test nbits == 16
    end

    @testset "wavwrite converts float values to 16-bit int wav" begin
        buf = SampleBuf(rand(16, 2), 48000)
        io = IOBuffer()
        SampledSignals.wavwrite(io, buf)
        samples, fs, nbits, opt = wavread(IOBuffer(takebuf_array(io)), format="native")
        @test samples == map(reinterpret, convert(Array{PCM16Sample}, buf))
        @test fs == 48000
        @test nbits == 16
    end
end
