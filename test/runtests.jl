using FastRunningMedian, Test, DataStructures, JLD2, OffsetArrays
import Statistics

"""
    check_health(mf::MedianFilter)

Check that all pointers point at a thing that again points back at them. Also check that low_heap is smaller than high_heap. 

Debug Function for MedianFilter. 
"""
function check_health(mf::MedianFilter)
    for k in 1:length(mf.heap_pos)
        current_heap, current_heap_ind = mf.heap_pos[k]
        if current_heap == true
            a = mf.low_heap[current_heap_ind][2] - mf.heap_pos_offset
            # println(k, " ?= ", a)
            @assert k == a
        else
            a = mf.high_heap[current_heap_ind][2] - mf.heap_pos_offset
            # println(k, " ?= ", a)
            @assert k == a
        end
    end

    if length(mf) >= 2
        @assert first(mf.low_heap) <= first(mf.high_heap)
    end
end

println("running tests...")

@testset "FastRunningMedian Tests" begin

    @testset "Stateful API Tests" begin
        
        @testset "Grow and Shrink Fuzz" begin
            # load test cases
            @load "fixtures/grow_shrink.jld2" grow_shrink_fixtures

            function grow_and_shrink_test(values, expected_medians)
                N = length(values)
                mf = MedianFilter(values[1], N)
                check_health(mf)
                @assert median(mf) == expected_medians[1]
                #grow phase
                for i in 2:N
                    grow!(mf, values[i])
                    check_health(mf)
                    @assert median(mf) == expected_medians[i]
                end
                # shrink phase
                for i in N+1:2N-1
                    shrink!(mf)
                    check_health(mf)
                    @assert median(mf) == expected_medians[i]
                end
                @assert length(mf) == 1
            end
            
            for fixture in grow_shrink_fixtures
                grow_and_shrink_test(fixture...)
            end
        end
        
        @testset "Roll Fuzz" begin
            #load test cases
            @load "fixtures/roll.jld2" roll_fixtures

            function roll_test(initial_values, roll_values, expected_medians)
                window_size = length(initial_values)
                mf = MedianFilter(initial_values[1], window_size)
                for i in 2:window_size
                    grow!(mf, initial_values[i])
                end
                @assert length(mf) == window_size
                for i in 1:length(roll_values)
                    roll!(mf, roll_values[i])
                    check_health(mf)
                    @assert median(mf) == expected_medians[i]
                end
            end

            for fixture in roll_fixtures
                roll_test(fixture...)
            end
        end

        @testset "Roll does work with window size 1" begin
            mf = MedianFilter(1., 1)
            roll!(mf, 2.)
            @test 2. == median(mf)
            roll!(mf, 1.)
            @test 1. == median(mf)
        end
    
        @testset "Grow! does not grow beyond capacity" begin
            mf = MedianFilter(1., 3)
            grow!(mf, 2.)
            grow!(mf, 3.)
            @test_throws ErrorException grow!(mf, 4.)
        end

        @testset "shrink! below 1-element errors" begin
            mf = MedianFilter(1., 4)
            @test_throws ErrorException shrink!(mf)
        end

        @testset "can only roll when capacity is exactly met" begin
            mf = MedianFilter(1., 3)
            grow!(mf, 2.)
            @test_throws ErrorException roll!(mf, 3.)
            grow!(mf, 3.)
            roll!(mf, 4.)
            shrink!(mf)
            @test_throws ErrorException roll!(mf, 5.)
        end
    end

    @testset "High Level API Tests" begin
        # Desired API
        # running_median(input::Array{T, 1}, window_size::Integer, tapering=:sym) where T <: Real
        # taperings:
        # :symmetric or :sym (window symmetric around returned point, length N-1 if even window, N if odd)
        # :asymmetric or :asym (window full length to one side, length length N+W-1 if odd W, N-1+W if even window)
        # :asymmetric_truncated or :asymtrunc (same as asymmetric, but truncated at ends to size of symmetric)
        # :none or :no (only full length window used, length N-W+1)
        # 
        # all these taperings are symmetrical in that they behave the same at each end of the array, only mirrored

        @testset "Basic API examples" begin
            @test_throws ErrorException running_median(zeros(0), 1)
            @test running_median([1.], 1) == [1.]
            @test running_median([1., 2., 3.], 1) == [1., 2., 3.]
            @test running_median([1., 4., 2., 1.], 3) == [1., 2., 2., 1.]
            @test running_median([1, 4, 2, 1], 3) == [1, 2, 2, 1]
            @test running_median([1, 4, 2, 1], 3, :asym) == [1, 2.5, 2, 2, 1.5, 1]
            @test running_median([1., 4., 2., 1.], 3, :sym) == [1., 2., 2., 1.]
            @test running_median([1., 4., 2., 1.], 3, :symmetric) == [1., 2., 2., 1.]
            @test running_median([1., 4., 2., 1.], 3, :asym) == [1., 2.5, 2., 2., 1.5, 1.]
            @test running_median([1., 4., 2., 1.], 3, :asymmetric) == [1., 2.5, 2., 2., 1.5, 1.]
            @test running_median([1., 4., 2., 1.], 3, :asym_trunc) == [2.5, 2., 2., 1.5]
            @test running_median([1., 4., 2., 1.], 3, :asymmetric_truncated) == [2.5, 2., 2., 1.5]
            @test running_median([1., 4., 2., 1.], 3, :no) == [2., 2.]
            @test running_median([1., 4., 2., 1.], 3, :none) == [2., 2.]
            @test running_median([1., 2., 1., 2., 1., 3.], 101) == [1., 1., 1., 2., 2., 3.]
            @test running_median([1., 1., 2., 1., 1., 1., 1., 1., 2., 1.], 99) == 
                [1., 1., 1., 1., 1., 1., 1., 1., 1., 1.]
        end

        @testset "Basic API Examples with OffsetArrays" begin
            for offset in (-999, -1, 1, 888)
                @test running_median(OffsetArray([1.], offset), 1) == [1.]
                @test running_median(OffsetArray([1., 2., 3.], offset), 1) == [1., 2., 3.]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3) == [1., 2., 2., 1.]
                @test running_median(OffsetArray([1, 4, 2, 1], offset), 3) == [1, 2, 2, 1]
                @test running_median(OffsetArray([1, 4, 2, 1], offset), 3, :asym) == [1, 2.5, 2, 2, 1.5, 1]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :sym) == [1., 2., 2., 1.]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :asym) == [1., 2.5, 2., 2., 1.5, 1.]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :asym_trunc) == [2.5, 2., 2., 1.5]
                @test running_median(OffsetArray([1., 4., 2., 1.], offset), 3, :no) == [2., 2.]
                @test running_median(OffsetArray([1., 2., 1., 2., 1., 3.], offset), 101) == [1., 1., 1., 2., 2., 3.]
                @test running_median(OffsetArray([1., 1., 2., 1., 1., 1., 1., 1., 2., 1.], offset), 99) == 
                    [1., 1., 1., 1., 1., 1., 1., 1., 1., 1.]
            end
        end
        
        @testset "Compare to Naive Symmetric Median" begin
            @load "fixtures/symmetric.jld2" fixtures
            for fixture in fixtures
                @test fixture[3] == running_median(fixture[1], fixture[2], :sym)
            end
        end

        @testset "Compare to Naive Asymmetric Median" begin
            @testset "Float Input" begin
                @load "fixtures/asymmetric.jld2" fixtures
                for fixture in fixtures
                    @test fixture[3] == running_median(fixture[1], fixture[2], :asym)
                end
            end

            @testset "Int Input" begin
                @load "fixtures/asymmetric_int.jld2" fixtures
                for fixture in fixtures
                    @test fixture[3] == running_median(fixture[1], fixture[2], :asym)
                end
            end
        end

        @testset "Compare to Untapered Median from RollingFunctions" begin
            @load "fixtures/untapered.jld2" untapered_fixtures
            for fixture in untapered_fixtures
                @test fixture[3] == running_median(fixture[1], fixture[2], :none)
            end
        end

        @testset "Compare to Naive Asymmetric Truncated Median" begin
            @load "fixtures/asym_trunc.jld2" asym_trunc_fixtures
            for fixture in asym_trunc_fixtures
                @test fixture[3] == running_median(fixture[1], fixture[2], :asym_trunc)
            end
        end

        @testset "Check views into arrays can be handled" begin
            data, window = collect(1:10), 3
            @test running_median(@view(data[2:end]), window) == running_median(data[2:end], window)
        end
        
    end
end # all tests