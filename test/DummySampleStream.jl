using Test
import Compat: undef

@testset "DummySampleStream Tests" begin
    DEFAULT_SR = 48000
    DEFAULT_T = Float32

    DummySource(buf) = DummySampleSource(DEFAULT_SR, buf)
    DummyMonoSink() = DummySampleSink(DEFAULT_T, DEFAULT_SR, 1)
    DummyStereoSink() = DummySampleSink(DEFAULT_T, DEFAULT_SR, 2)

    @testset "supports audio interface" begin
        data = rand(DEFAULT_T, (64, 2))
        source = DummySource(data)
        @test samplerate(source) == DEFAULT_SR
        @test nchannels(source) == 2
        sink = DummyStereoSink()
        @test samplerate(sink) == DEFAULT_SR
        @test nchannels(sink) == 2
        @test eltype(source) == DEFAULT_T
    end

    @testset "can be created with non-unit sampling rate" begin
        sink = DummySampleSink(Float32, 48000, 2)
        @test samplerate(sink) == 48000
        source = DummySampleSource(48000, Array{Float32}(undef, 16, 2))
        @test samplerate(source) == 48000
    end
end
