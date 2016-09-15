@testset "SampleBuf Tests" begin
    TEST_SR = 48000Hz
    TEST_T = Float32
    Buf(arr) = SampleBuf(arr, TEST_SR)

    @testset "Supports audio interface" begin
        tbuf = Buf(zeros(TEST_T, 64, 2))
        @test samplerate(tbuf) == TEST_SR
        @test nchannels(tbuf) == 2
        @test nframes(tbuf) == 64
        @test domain(tbuf) == collect((0:63)/TEST_SR)
        @test domain(tbuf, units=false) == map(float, (0:63)/TEST_SR)
        ret = samplerate!(tbuf, 24000Hz)
        @test samplerate(tbuf) == 24000Hz
        @test ret === tbuf
    end

    @testset "Supports size()" begin
        buf = Buf(zeros(TEST_T, 64, 2))
        @test size(buf) == (64, 2)
    end

    @testset "Can get type params from contained array" begin
        timebuf = SampleBuf(Array(TEST_T, 32, 2), TEST_SR)
        @test nframes(timebuf) == 32
        @test nchannels(timebuf) == 2
    end

    @testset "supports equality" begin
        arr1 = rand(TEST_T, (64, 2))
        arr2 = arr1 + 1
        arr3 = arr1[:, 1]
        buf1 = SampleBuf(arr1, TEST_SR)
        buf2 = SampleBuf(arr1, TEST_SR)
        buf3 = SampleBuf(arr1, TEST_SR+1Hz)
        buf4 = SampleBuf(arr2, TEST_SR)
        buf5 = SampleBuf(arr3, TEST_SR)
        buf6 = SampleBuf(arr1, 1/TEST_SR)
        @test buf1 == buf2
        @test buf2 != buf3
        @test buf2 != buf4
        @test buf2 != buf5
        @test buf1 != buf6
    end


    @testset "Can be indexed with 1D indices" begin
        arr = TEST_T[1:8 9:16]
        buf = SampleBuf(arr, TEST_SR)
        buf[12] = 1.5
        @test buf[12] == 1.5
    end

    @testset "Can be indexed with 2D indices" begin
        arr = TEST_T[1:8 9:16]
        buf = SampleBuf(arr, TEST_SR)
        buf[5, 2] = 1.5
        @test buf[5, 2] == 1.5
    end

    @testset "Can be indexed with 1D ranges" begin
        arr = TEST_T[1:8 9:16]
        buf = SampleBuf(arr, TEST_SR)
        # linear indexing gives you a mono buffer
        slice = buf[6:12]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(TEST_T[6:12;], TEST_SR)
        @test samplerate(buf[:]) == TEST_SR
        @test buf[:] == SampleBuf(arr[:], TEST_SR)
    end

    @testset "can be indexed with 2D ranges" begin
        arr = TEST_T[1:8 9:16]
        buf = SampleBuf(arr, TEST_SR)
        slice = buf[3:6, 1:2]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(TEST_T[3:6 11:14], TEST_SR)
        # make sure it works with a bare colon
        slice = buf[3:6, :]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(TEST_T[3:6 11:14], TEST_SR)
        slice = buf[:, 1:2]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(TEST_T[1:8 9:16], TEST_SR)
        slice = buf[:, :]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(TEST_T[1:8 9:16], TEST_SR)
    end

    @testset "can be sliced in 1D" begin
        arr = TEST_T[1:8 9:16]
        buf = SampleBuf(arr, TEST_SR)
        slice = buf[6, 1:2]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(TEST_T[6 14], TEST_SR)
        @test samplerate(slice) == TEST_SR
        slice = buf[3:6, 1]
        @test slice == SampleBuf(TEST_T[3:6;], TEST_SR)
    end

    @testset "can be indexed with Intervals" begin
        arr = TEST_T[1:8 9:16]
        buf = SampleBuf(arr, TEST_SR)
        # linear indexing gives you a mono buffer
        slice = buf[6..12]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(arr[6:12], TEST_SR)
        slice = buf[2..6, 1]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(arr[2:6, 1], TEST_SR)
        slice = buf[2, 1..2]
        @test samplerate(slice) == TEST_SR
        # 0.5 array indexing drops scalar indices, so we use 2:2 instead of 2
        @test slice == SampleBuf(arr[2:2, 1:2], TEST_SR)
        slice = buf[2..6, 1..2]
        @test samplerate(slice) == TEST_SR
        @test slice == SampleBuf(arr[2:6, 1:2], TEST_SR)
    end

    @testset "Can be indexed with bool arrays" begin
        arr = TEST_T[1:8;]
        buf = SampleBuf(arr, TEST_SR)
        idxs = falses(length(buf))
        idxs[[1, 3, 5]] = true
        arr[idxs]
        @test buf[idxs] == SampleBuf(arr[idxs], TEST_SR)
    end

    @testset "Channel pointer" begin
        arr = rand(Float64, 10, 4)
        buf = SampleBuf(arr, TEST_SR)
        for ch in 1:4
            @test unsafe_load(channelptr(buf, ch)) == arr[1, ch]
        end
    end

    @testset "Nice syntax for creating buffers" begin
        buf = SampleBuf(Float32, TEST_SR, 100, 2)
        @test nchannels(buf) == 2
        @test nframes(buf) == 100
        @test eltype(buf) == Float32
        @test samplerate(buf) == TEST_SR
    end

    @testset "Can be created without units" begin
        buf = SampleBuf(Float32, 48000, 100, 2)
        @test samplerate(buf) == 48000
        buf = SampleBuf(Array(Float32, 100, 2), 48000)
        @test samplerate(buf) == 48000
    end

    @testset "sub references the original instead of copying" begin
        arr = rand(TEST_T, 16)
        buf = SampleBuf(arr, TEST_SR)

        v = view(buf, 5:10)
        @test v[1] == buf[5]
        buf[6] = 0.0
        v[2] = 42.0
        @test buf[6] == 42.0
    end

    @testset "Invalid units throw an error" begin
        arr = rand(TEST_T, (round(Int, 0.01s*TEST_SR), 2))
        buf = SampleBuf(arr, TEST_SR)
        @test_throws MethodError buf[1*SIUnits.Ampere]
    end

    @testset "SampleBufs can be indexed in seconds" begin
        # array with 10ms of audio
        arr = rand(TEST_T, (round(Int, 0.01s*TEST_SR), 2))
        buf = SampleBuf(arr, TEST_SR)
        @test buf[0.0s] == arr[1]
        @test buf[0.005s] == arr[241]
        @test buf[0.005s, 1] == arr[241, 1]
        @test buf[0.005s, 2] == arr[241, 2]
        @test buf[0.004s..0.005s] == SampleBuf(arr[193:241], TEST_SR)
        @test buf[0.004s..0.005s, 2] == SampleBuf(arr[193:241, 2], TEST_SR)
        @test buf[0.004s..0.005s, 1:2] == SampleBuf(arr[193:241, 1:2], TEST_SR)

        # throws an error if we sample non-unit buffer
        buf2 = SampleBuf(arr, 48000)
        @test_throws ErrorException buf2[0.005s]
    end

    @testset "Frequency-domain SampleBufs can be indexed in Hz" begin
        N = 512
        arr = rand(TEST_T, N, 2)
        buf = SampleBuf(arr, N / TEST_SR)
        @test buf[0.0Hz] == arr[1]
        @test buf[843.75Hz] == arr[10]
        @test buf[843.75Hz, 1] == arr[10, 1]
        @test buf[843.75Hz, 2] == arr[10, 2]
    end

    @testset "Supports arithmetic" begin
        arr1 = rand(TEST_T, 4, 2)
        arr2 = rand(TEST_T, 4, 2)
        buf1 = SampleBuf(arr1, TEST_SR)
        buf2 = SampleBuf(arr2, TEST_SR)

        sum = buf1 + buf2
        @test sum == SampleBuf(arr1 + arr2, TEST_SR)
        @test typeof(sum) == typeof(buf1)
        prod = buf1 .* buf2
        @test prod == SampleBuf(arr1 .* arr2, TEST_SR)
        @test typeof(prod) == typeof(buf1)
        diff = buf1 - buf2
        @test diff == SampleBuf(arr1 - arr2, TEST_SR)
        @test typeof(diff) == typeof(buf1)
        quot = buf1 ./ buf2
        @test quot == SampleBuf(arr1 ./ arr2, TEST_SR)
        @test typeof(quot) == typeof(buf1)
    end

    @testset "Arithmetic with constants gives SampleBufs" begin
        arr1 = rand(TEST_T, 4, 2)
        buf1 = SampleBuf(arr1, TEST_SR)

        sum = buf1 + 2.0f0
        @test sum == SampleBuf(arr1 + 2.0f0, TEST_SR)
        @test typeof(sum) == typeof(buf1)
        prod = buf1 * 2.0f0
        @test prod == SampleBuf(arr1 * 2.0f0, TEST_SR)
        @test typeof(prod) == typeof(buf1)
        diff = buf1 - 2.0f0
        @test diff == SampleBuf(arr1 - 2.0f0, TEST_SR)
        @test typeof(diff) == typeof(buf1)
        quot = buf1 / 2.0f0
        @test quot == SampleBuf(arr1 / 2.0f0, TEST_SR)
        @test typeof(quot) == typeof(buf1)
    end

    @testset "Arithmetic with arrays gives SampleBufs" begin
        arr1 = rand(TEST_T, 4, 2)
        arr2 = rand(TEST_T, 4, 2)
        buf1 = SampleBuf(arr1, TEST_SR)

        sum = buf1 + arr2
        @test sum == SampleBuf(arr1 + arr2, TEST_SR)
        @test typeof(sum) == typeof(buf1)
        prod = buf1 .* arr2
        @test prod == SampleBuf(arr1 .* arr2, TEST_SR)
        @test typeof(prod) == typeof(buf1)
        diff = buf1 - arr2
        @test diff == SampleBuf(arr1 - arr2, TEST_SR)
        @test typeof(diff) == typeof(buf1)
        quot = buf1 ./ arr2
        @test quot == SampleBuf(arr1 ./ arr2, TEST_SR)
        @test typeof(quot) == typeof(buf1)
    end

    @testset "Arithmetic with linspace gives SampleBufs" begin
        arr1 = rand(TEST_T, 4)
        arr2 = linspace(0.0f0, 1.0f0, 4)
        buf1 = SampleBuf(arr1, TEST_SR)

        sum = buf1 + arr2
        @test sum == SampleBuf(arr1 + arr2, TEST_SR)
        @test typeof(sum) == typeof(buf1)
        prod = buf1 .* arr2
        @test prod == SampleBuf(arr1 .* arr2, TEST_SR)
        @test typeof(prod) == typeof(buf1)
        diff = buf1 - arr2
        @test diff == SampleBuf(arr1 - arr2, TEST_SR)
        @test typeof(diff) == typeof(buf1)
        quot = buf1 ./ arr2
        @test quot == SampleBuf(arr1 ./ arr2, TEST_SR)
        @test typeof(quot) == typeof(buf1)
    end

    @testset "FFT of SampleBuf gives FrequencySampleBuf" begin
        arr = rand(TEST_T, 512)
        buf = SampleBuf(arr, TEST_SR)
        spec = fft(buf)
        @test isa(spec, SampleBuf)
        @test eltype(spec) == Complex{TEST_T}
        @test samplerate(spec) == 512//TEST_SR
        @test nchannels(spec) == 1
        @test spec == SampleBuf(fft(arr), 512//TEST_SR)
        buf2 = ifft(spec)
        # TODO: real time signals should become symmetric spectra, and then
        # back to real time signals with ifft
        @test isa(buf2, SampleBuf)
        @test eltype(buf2) == Complex{TEST_T}
        @test samplerate(buf2) == TEST_SR
        @test nchannels(buf2) == 1
        @test isapprox(buf2, buf)
    end

    @testset "multichannel buf prints prettily" begin
        t = collect(linspace(0, 2pi, 300))
        buf = SampleBuf([cos(t) sin(t)]*0.2, 48000Hz)
        expected = """300-frame, 2-channel SampleBuf{Float64, 2, SIUnits.SIQuantity{$Int,0,0,-1,0,0,0,0,0,0}}
                   0.00625 s at 48000 s⁻¹
                   ▆▆▆▆▆▆▆▆▆▆▅▅▅▅▅▅▄▄▃▃▄▄▅▅▅▅▅▅▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▅▅▅▅▅▅▄▄▃▃▄▄▅▅▅▅▅▅▆▆▆▆▆▆▆▆▆▆
                   ▃▄▄▅▅▅▅▅▅▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▅▅▅▅▅▅▄▄▂▄▄▅▅▅▅▅▅▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▅▅▅▅▅▅▄▄▃"""
        iobuf = IOBuffer()
        display(TextDisplay(iobuf), buf)
        @test takebuf_string(iobuf) == expected
    end
    @testset "1D buf prints prettily" begin
        t = collect(linspace(0, 2pi, 300))
        buf = SampleBuf(cos(t)*0.2, 48000Hz)
        expected = """300-frame, 1-channel SampleBuf{Float64, 1, SIUnits.SIQuantity{$Int,0,0,-1,0,0,0,0,0,0}}
                   0.00625 s at 48000 s⁻¹
                   ▆▆▆▆▆▆▆▆▆▆▅▅▅▅▅▅▄▄▃▃▄▄▅▅▅▅▅▅▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▅▅▅▅▅▅▄▄▃▃▄▄▅▅▅▅▅▅▆▆▆▆▆▆▆▆▆▆"""
        iobuf = IOBuffer()
        display(TextDisplay(iobuf), buf)
        @test takebuf_string(iobuf) == expected
    end
    @testset "zero-length buf prints prettily" begin
        buf = SampleBuf(Float64, 48000Hz, 0, 2)
        expected = """0-frame, 2-channel SampleBuf{Float64, 2, SIUnits.SIQuantity{$Int,0,0,-1,0,0,0,0,0,0}}
                   0.0 s at 48000 s⁻¹"""
        iobuf = IOBuffer()
        display(TextDisplay(iobuf), buf)
        @test takebuf_string(iobuf) == expected
    end
end
