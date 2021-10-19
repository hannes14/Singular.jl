###############################################################################
#
#   WeylPolyRing/sweylpoly
#
###############################################################################

const WeylPolyRingID = Dict{Tuple{Union{Ring, Field}, Array{Symbol, 1},
         libSingular.rRingOrder_t, libSingular.rRingOrder_t, Int},
                                                      AbstractAlgebra.NCRing}()

mutable struct WeylPolyRing{T <: Nemo.RingElem} <: AbstractAlgebra.NCRing
   ptr::libSingular.ring_ptr
   refcount::Int
   base_ring::Union{Ring, Field}
   ord::Symbol
   S::Vector{Symbol}

   function WeylPolyRing{T}(R::Union{Ring, Field}, s::Array{Symbol, 1},
         ord_sym::Symbol, cached::Bool = true,
         ordering::libSingular.rRingOrder_t = ringorder_dp,
         ordering2::libSingular.rRingOrder_t = ringorder_C,
         degree_bound::Int = 0) where T

      length(s) > 0 && iseven(length(s)) || error("need an even number of indeterminates")

      # check ordering: accept exactly one of ringorder_c, ringorder_C
      if (((ordering == ringorder_c || ordering == ringorder_C)
               && (ordering2 == ringorder_c || ordering2 == ringorder_C))
            || ((ordering != ringorder_c && ordering != ringorder_C)
               && (ordering2 != ringorder_c && ordering2 != ringorder_C)))
         error("wrong ordering")
      end
      bitmask = Culong(degree_bound)
      n_vars = Cint(length(s));
      # internally in libSingular, degree_bound is set to
      degree_bound_adjusted = Int(libSingular.rGetExpSize(bitmask, n_vars))
      if haskey(WeylPolyRingID, (R, s, ordering, ordering2, degree_bound_adjusted))
         return WeylPolyRingID[R, s, ordering, ordering2,
               degree_bound_adjusted]::WeylPolyRing{T}
      else
         v = [pointer(Base.Vector{UInt8}(string(str)*"\0")) for str in s]
         r = libSingular.nCopyCoeff(R.ptr)
         
         blk0 = unsafe_wrap(Array, Ptr{Cint}(libSingular.omAlloc0(Csize_t(3*sizeof(Cint)))), 3; own=false)
         blk1 = unsafe_wrap(Array, Ptr{Cint}(libSingular.omAlloc0(Csize_t(3*sizeof(Cint)))), 3; own=false)
         if (ordering == ringorder_c || ordering == ringorder_C)
            blk0[1] = Cint(0)
            blk1[1] = Cint(0)
            blk0[2] = Cint(1)
            blk1[2] = Cint(length(v))
         else
            blk0[1] = Cint(1)
            blk1[1] = Cint(length(v))
            blk0[2] = Cint(0)
            blk1[2] = Cint(0)
         end
         ord = Array{libSingular.rRingOrder_t, 1}(undef, 3)
         ord[1] = ordering
         ord[2] = ordering2
         ord[3] = ringorder_no
         ptr = libSingular.rWeyl(r, v, ord, blk0, blk1, bitmask)
         @assert degree_bound_adjusted == Int(libSingular.rBitmask(ptr))
         d = WeylPolyRingID[R, s, ordering, ordering2, degree_bound_adjusted] =
               new(ptr, 1, R, ord_sym, s)
         finalizer(_WeylPolyRing_clear_fn, d)
         return d
      end
   end
end

function (R::WeylPolyRing{T})(r::libSingular.ring_ptr) where T
    new_r = deepcopy(R)
    new_ptr = new_r.ptr
    new_r.ptr = r
    return new_r
end

function _WeylPolyRing_clear_fn(R::WeylPolyRing)
   R.refcount -= 1
   if R.refcount == 0
      libSingular.rDelete(R.ptr)
   end
end

mutable struct sweylpoly{T <: Nemo.RingElem} <: AbstractAlgebra.NCRingElem
   ptr::libSingular.poly_ptr
   parent::WeylPolyRing{T}

   function sweylpoly{T}(R::WeylPolyRing{T}) where T <: Nemo.RingElem
      p = libSingular.p_ISet(0, R.ptr)
      z = new{T}(p, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end
    
   function sweylpoly{T}(R::WeylPolyRing{T}, p::libSingular.poly_ptr) where T <: Nemo.RingElem
      z = new{T}(p, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end
    
   function sweylpoly{T}(R::WeylPolyRing{T}, p::T) where T <: Nemo.RingElem
      n = libSingular.n_Copy(p.ptr, parent(p).ptr)
      r = libSingular.p_NSet(n, R.ptr)
      z = new{T}(r, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end
    
   function sweylpoly{T}(R::WeylPolyRing{T}, n::libSingular.number_ptr) where T <: Nemo.RingElem
      nn = libSingular.n_Copy(n, base_ring(R).ptr)
      p = libSingular.p_NSet(nn, R.ptr)
      z = new{T}(p, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end

   function sweylpoly{T}(R::WeylPolyRing{T}, n::Ptr{Cvoid}) where T <: Nemo.RingElem
      p = libSingular.p_NSet(n, R.ptr)
      z = new(p, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end

   function sweylpoly{T}(R::WeylPolyRing{T}, b::Int) where T <: Nemo.RingElem
      p = libSingular.p_ISet(b, R.ptr)
      z = new{T}(p, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end

   function sweylpoly{T}(R::WeylPolyRing{T}, b::BigInt) where T <: Nemo.RingElem
      n = libSingular.n_InitMPZ(b, R.base_ring.ptr)
      p = libSingular.p_NSet(n, R.ptr)
      z = new{T}(p, R)
      R.refcount += 1
      finalizer(_sweylpoly_clear_fn, z)
      return z
   end
end

function _sweylpoly_clear_fn(p::sweylpoly)
   R = parent(p)
   libSingular.p_Delete(p.ptr, R.ptr)
   _WeylPolyRing_clear_fn(R)
end

