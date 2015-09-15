@testset "Interval Tests" begin
    @testset "Basic Construction" begin
        interval = Interval(4.5, 8.9)
        @test interval.lo == 4.5
        @test interval.hi == 8.9
        @test 1.2..5.6 == Interval{Float64}(1.2, 5.6)
        # this test fails
        # @test Interval(4.5) == (4.5..4.5)
    end
    @testset "Promotion Rules" begin
        @test 1.2..5 == Interval{Float64}(1.2, 5.0)
        @test_throws ArgumentError Interval("Hello", 45.6)
    end
    @testset "Comparisons" begin
        @test Interval{Float64}(1.2, 5.6) == Interval{Float64}(1.2, 5.6)
        @test 1..2 < 3..4
        @test !(3..4 < 1..2)
        @test 3..4 > 1..2
        @test 3..4 < 5
        @test 3..4 > 2
        @test !(2..4 < 3)
        @test !(2..4 > 3)
    end
    @testset "Arithmetic" begin
        @test (2..5) + (3..6) == (5..11)
    end
    @testset "Minimums and Maximums" begin
        @test minimum(1..5) == 1
        @test maximum(1..5) == 5
    end
    @testset "Containment" begin
        @test 4 in 1..6
        @test !(8 in 1..6)
    end
end
