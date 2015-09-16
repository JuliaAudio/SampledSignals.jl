# This is copied from @mbauman's AxisArrays package, with some things removed
# and a few small things added

@doc """
An Interval represents all values between and including its two endpoints.
Intervals are parameterized by the type of its endpoints; this type must be
a concrete leaf type that supports a partial ordering. Promoting arithmetic
is defined for Intervals of `Number` and `Dates.AbstractTime`.

### Type parameters

```julia
immutable Interval{T}
```
* `T` : the type of the interval's endpoints. Must be a concrete leaf type.

### Constructors

```julia
Interval(a, b)
a .. b
```

### Arguments

* `a` : lower bound of the interval
* `b` : upper bound of the interval

### Examples

```julia
A = AxisArray(collect(1:20), Axis{:time}(.1:.1:2.0))
A[Interval(0.2,0.5)]
A[0.0 .. 0.5]
```

""" ->
immutable Interval{T}
    lo::T
    hi::T
    function Interval(lo, hi)
        lo <= hi ? new(lo, hi) : throw(ArgumentError("lo must be less than or equal to hi"))
    end
end
Interval{T}(a::T,b::T) = Interval{T}(a,b)
# Allow promotion during construction, but only if it results in a leaf type
function Interval{T,S}(a::T, b::S)
    R = promote_type(T,S)
    isleaftype(R) || throw(ArgumentError("cannot promote $a and $b to a common leaf type"))
    Interval{R}(promote(a,b)...)
end
const .. = Interval

Base.print(io::IO, i::Interval) = print(io, "$(i.lo)..$(i.hi)")

Base.convert{T}(::Type{Interval{T}}, x::T) = Interval{T}(x,x)
Base.convert{T,S}(::Type{Interval{T}}, x::S) = (y=convert(T, x); Interval{T}(y,y))
Base.convert{T}(::Type{Interval{T}}, w::Interval) = Interval{T}(convert(T, w.lo), convert(T, w.hi))

# Promotion rules for "promiscuous" types like Intervals and SIUnits, which both
# simply wrap any Number, are often ambiguous. That is, which type should "win"
# -- is the promotion between an SIUnit and an Interval an SIQuantity{Interval}
# or is it an Interval{SIQuantity}? For our uses in AxisArrays, though, we can
# sidestep this problem by making Intervals *not* a subtype of Number. Then in
# order for them to plug into the promotion system, we *extend* the promoting
# operator behaviors to Union{Number, Interval}. This way other types can
# similarly define their own extensions to the promoting operators without fear
# of ambiguity -- there will simply be, e.g.,
#
# f(x::Number, y::Number) = f(promote(x,y)...) # in base
# f(x::Union{Number, Interval}, y::Union{Number, Interval}) = f(promote(x,y)...)
# f(x::Union{Number, T}, y::Union{Number, T}) = f(promote(x,y)...)
#
# In this way, these "promiscuous" types will never interact unless explicitly
# made subtypes of Number or otherwise defined with knowledge of eachother. The
# downside is that Intervals are not as useful as they could be; they really
# could be considered as <: Number themselves. We do this in general for any
# supported Scalar:
typealias Scalar Union{Number, Dates.AbstractTime}
Base.promote_rule{T<:Scalar}(::Type{Interval{T}}, ::Type{T}) = Interval{T}
Base.promote_rule{T,S<:Scalar}(::Type{Interval{T}}, ::Type{S}) = Interval{promote_type(T,S)}
Base.promote_rule{T,S}(::Type{Interval{T}}, ::Type{Interval{S}}) = Interval{promote_type(T,S)}

import Base: ==, +, -, *, /, ^
==(a::Interval, b::Interval) = a.lo == b.lo && a.hi == b.hi
const _interval_hash = UInt == UInt64 ? 0x1588c274e0a33ad4 : 0x1e3f7252
Base.hash(a::Interval, h::UInt) = hash(a.lo, hash(a.hi, hash(_interval_hash, h)))

Base.in(a, b::Interval) = b.lo <= a <= b.hi
Base.in(a::Interval, b::Interval) = b.lo <= a.lo && a.hi <= b.hi
Base.minimum(a::Interval) = a.lo
Base.maximum(a::Interval) = a.hi
