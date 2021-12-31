"""
```julia
nanpctile!(A, p; dims)
```
Compute the `p`th percentile (where `p ∈ [0,100]`) of all elements in `A`,
optionally over dimensions specified by `dims`.

As `StatsBase.percentile`, but in-place, ignoring `NaN`s, and supporting the `dims` keyword.

Be aware that, like `Statistics.median!`, this function modifies `A`, sorting or
partially sorting the contents thereof (specifically, along the dimensions specified
by `dims`, using either `quicksort!` or `quickselect!` depending on the size
of the array). Do not use this function if you do not want the contents of `A`
to be rearranged.

Reduction over multiple `dims` is not officially supported, though does work
(in generally suboptimal time) as long as the dimensions being reduced over are
all contiguous.

## Examples
```julia
julia> using VectorizedStatistics

julia> A = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

 julia> nanpctile!(A, 50, dims=1)
 1×3 Matrix{Float64}:
  4.0  5.0  6.0

 julia> nanpctile!(A, 50, dims=2)
 3×1 Matrix{Float64}:
  2.0
  5.0
  8.0

 julia> nanpctile!(A, 50)
 5.0

 julia> A # Note that the array has been sorted
3×3 Matrix{Int64}:
 1  4  7
 2  5  8
 3  6  9
```
"""
nanpctile!(A, p::Number; dims=:) = _nanquantile!(A, 0.01*p, dims)
export nanpctile!


"""
```julia
nanquantile!(A, q; dims)
```
Compute the `q`th quantile (where `q ∈ [0,1]`) of all elements in `A`,
optionally over dimensions specified by `dims`.

Similar to `StatsBase.quantile!`, but slightly vectorized, and supporting the `dims` keyword.

Be aware that, like `StatsBase.quantile!`, this function modifies `A`, sorting or
partially sorting the contents thereof (specifically, along the dimensions specified
by `dims`, using either `quicksort!` or `quickselect!` depending on the size
of the array). Do not use this function if you do not want the contents of `A`
to be rearranged.

Reduction over multiple `dims` is not officially supported, though does work
(in generally suboptimal time) as long as the dimensions being reduced over are
all contiguous.

## Examples
```julia
julia> using VectorizedStatistics

julia> A = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

 julia> nanquantile!(A, 0.5, dims=1)
 1×3 Matrix{Float64}:
  4.0  5.0  6.0

 julia> nanquantile!(A, 0.5, dims=2)
 3×1 Matrix{Float64}:
  2.0
  5.0
  8.0

 julia> nanquantile!(A, 0.5)
 5.0

 julia> A # Note that the array has been sorted
3×3 Matrix{Int64}:
 1  4  7
 2  5  8
 3  6  9
```
"""
nanquantile!(A, q::Number; dims=:) = _nanquantile!(A, q, dims)
export nanquantile!

# Reduce one dim
_nanquantile!(A, q::Real, dims::Int) = _nanquantile!(A, q, (dims,))

# Reduce some dims
function _nanquantile!(A::AbstractArray{T,N}, q::Real, dims::Tuple) where {T,N}
    sᵢ = size(A)
    sₒ = ntuple(Val(N)) do d
        ifelse(d ∈ dims, 1, sᵢ[d])
    end
    Tₒ = Base.promote_op(/, T, Int)
    B = similar(A, Tₒ, sₒ)
    _nanquantile!(B, A, q, dims)
end

# Reduce all the dims!
_nanquantile!(A, q::Real, ::Tuple{Colon}) = _nanquantile!(A, q, :)
function _nanquantile!(A, q::Real, ::Colon)
    iₗ, iᵤ = firstindex(A), lastindex(A)
    A, iₗ, iᵤ₋ = sortnans!(A, iₗ, iᵤ)

    N₋ = iᵤ - iₗ
    iₚ = q*N₋ + iₗ
    iₚ₋ = floor(Int, iₚ)
    iₚ₊ = ceil(Int, iₚ)
    if N₋ < 384
        quicksort!(A, iₗ, iᵤ)
    else
        quickselect!(A, iₗ, iᵤ, iₚ₋)
        quickselect!(A, iₚ₊, iᵤ, iₚ₊)
    end
    f = iₚ - iₚ₋
    return f*A[iₚ₊] + (1-f)*A[iₚ₋]
end

# Generate customized set of loops for a given ndims and a vector
# `static_dims` of dimensions to reduce over
function staticdim_quantile_quote(static_dims::Vector{Int}, N::Int)
  M = length(static_dims)
  # `static_dims` now contains every dim we're taking the quantile over.
  Bᵥ = Expr(:call, :view, :B)
  Aᵥ = Expr(:call, :view, :A)
  reduct_inds = Int[]
  nonreduct_inds = Int[]
  # Firstly, build our expressions for indexing each array
  Aind = :(Aᵥ[])
  Bind = :(Bᵥ[])
  inds = Vector{Symbol}(undef, N)
  for n ∈ 1:N
    ind = Symbol(:i_,n)
    inds[n] = ind
    if n ∈ static_dims
      push!(reduct_inds, n)
      push!(Aᵥ.args, :)
      push!(Bᵥ.args, :(firstindex(B,$n)))
    else
      push!(nonreduct_inds, n)
      push!(Aᵥ.args, ind)
      push!(Bᵥ.args, :)
      push!(Bind.args, ind)
    end
  end
  # Secondly, build up our set of loops
  if !isempty(nonreduct_inds)
    firstn = first(nonreduct_inds)
    block = Expr(:block)
    loops = Expr(:for, :($(inds[firstn]) = indices((A,B),$firstn)), block)
    if length(nonreduct_inds) > 1
      for n ∈ @view(nonreduct_inds[2:end])
        newblock = Expr(:block)
        push!(block.args, Expr(:for, :($(inds[n]) = indices((A,B),$n)), newblock))
        block = newblock
      end
    end
    rblock = block
    # Push more things here if you want them at the beginning of the reduction loop
    push!(rblock.args, :(Aᵥ = $Aᵥ))
    push!(rblock.args, :($Bind = _nanquantile!(Aᵥ, q, :)))
    # Put it all together
    return quote
      Bᵥ = $Bᵥ
      @inbounds $loops
      return B
    end
  else
    return quote
      Bᵥ = $Bᵥ
      Bᵥ[] = _nanquantile!(A, q, :)
      return B
    end
  end
end

# Chris Elrod metaprogramming magic:
# Turn non-static integers in `dims` tuple into `StaticInt`s
# so we can construct `static_dims` vector within @generated code
function branches_quantile_quote(N::Int, M::Int, D)
  static_dims = Int[]
  for m ∈ 1:M
    param = D.parameters[m]
    if param <: StaticInt
      new_dim = _dim(param)::Int
      @assert new_dim ∉ static_dims
      push!(static_dims, new_dim)
    else
      t = Expr(:tuple)
      for n ∈ static_dims
        push!(t.args, :(StaticInt{$n}()))
      end
      q = Expr(:block, :(dimm = dims[$m]))
      qold = q
      ifsym = :if
      for n ∈ 1:N
        n ∈ static_dims && continue
        tc = copy(t)
        push!(tc.args, :(StaticInt{$n}()))
        qnew = Expr(ifsym, :(dimm == $n), :(return _nanquantile!(B, A, q, $tc)))
        for r ∈ m+1:M
          push!(tc.args, :(dims[$r]))
        end
        push!(qold.args, qnew)
        qold = qnew
        ifsym = :elseif
      end
      # Else, if dimm ∉ 1:N, drop it from list and continue
      tc = copy(t)
      for r ∈ m+1:M
        push!(tc.args, :(dims[$r]))
      end
      push!(qold.args, Expr(:block, :(return _nanquantile!(B, A, q, $tc))))
      return q
    end
  end
  return staticdim_quantile_quote(static_dims, N)
end

# Efficient @generated in-place quantile
@generated function _nanquantile!(B::AbstractArray{Tₒ,N}, A::AbstractArray{T,N}, q::Real, dims::D) where {Tₒ,T,N,M,D<:Tuple{Vararg{Integer,M}}}
  branches_quantile_quote(N, M, D)
end
@generated function _nanquantile!(B::AbstractArray{Tₒ,N}, A::AbstractArray{T,N}, q::Real, dims::Tuple{}) where {Tₒ,T,N}
  :(copyto!(B, A); return B)
end
