# import Base:getindex, setindex!, show, read, write, isequal, ==, isempty, sizeof, copy, hash
export InstrumentResponse, GenResp, PZResp, PZResp64

@doc """
**InstrumentResponse**

An abstract type whose subtypes (PZResp) describe instrument frequency responses.

Additional structures can be added for custom types.

""" InstrumentResponse
abstract type InstrumentResponse end

function showresp_full(io::IO, Resp::T) where {T<:InstrumentResponse}
  F = fieldnames(T)
  println(io, T, " with fields:")
  for f in F
    fn = lpad(String(f), 5, " ")
    println(io, fn, ": ", getfield(Resp,f))
  end
  return nothing
end

function resptyp2code(Resp::InstrumentResponse)
  T = typeof(Resp)
  c = UInt8(
  if T == PZResp
    0x01
  elseif T == PZResp64
    0x02
  else
    0x00
  end
  )
  return c
end

function code2resptyp(c::UInt8)
  if c == 0x00
    return GenResp
  elseif c == 0x01
    return PZResp
  elseif c == 0x02
    return PZResp64
  end
end

copy(R::T) where {T<:InstrumentResponse} = deepcopy(R)

"""
    GenResp

Generic instrument response with two fields:
* desc::String (descriptive string)
* resp::Array{Complex{Float64},2}
"""
mutable struct GenResp <: InstrumentResponse
  desc::String
  resp::Array{Complex{Float64},2}
  function GenResp(S::String, X::Array{Complex{Float64},2}) where {T<:Complex}
    return new(S, X)
  end
end

# GenResp default
GenResp(;
          desc::String              = "",
          resp::Array{Complex{Float64},2} = Array{Complex{Float64},2}(undef, 0, 0)
        ) = GenResp(desc, resp)
GenResp(X::Array{Complex{Float64},2}) = GenResp(desc = "", resp = X)

# How we read from file
GenResp(s::String, X::Array{T,2}, Y::Array{T,2}) where {T <: Real} = GenResp(s, complex.(Float64.(X), Float64.(Y)))

getindex(x::GenResp, i::Int64) = getindex(getfield(x, :resp), i)
getindex(x::GenResp, i::Int64, j::Int64) = getindex(getfield(x, :resp), i, j)
setindex!(x::GenResp, y::Number, i::Int64) = setindex!(getfield(x, :resp), complex(y), i)
setindex!(x::GenResp, y::Number, i::Int64, j::Int64) = setindex!(getfield(x, :resp), complex(y), i, j)

function show(io::IO, Resp::GenResp)
  if get(io, :compact, false) == false
    showresp_full(io, Resp)
  else
    resp = getfield(Resp, :resp)
    M,N = size(resp)
    M1 = min(M,2)
    N1 = min(N,2)
    print(io, "[")
    for i = 1:M1
      for j = 1:N1
        print(io, repr(resp[i,j], context=:compact=>true))
        if j == N1 && i < M1
          if N > N1
            print(io, " … ")
          end
          print(io, "; ")
        elseif j == N1 && i == M1
          if N > N1
            print(io, " … ;")
          end
          if M > M1
            print(io, " … ")
          end
          print(io, "]")
        else
          print(io, ", ")
        end
      end
    end
    print(io, " (")
    print(io, getfield(Resp, :desc))
    print(io, ")")
  end
  return nothing
end

function write(io::IO, R::GenResp)
  write(io, Int64(sizeof(R.desc)))
  write(io, getfield(R, :desc))

  nr, nc = size(R.resp)
  write(io, Int64(nr))
  write(io, Int64(nc))
  write(io, getfield(R, :resp))
  return nothing
end

read(io::IO, ::Type{GenResp}) = GenResp(
  String(read(io, read(io, Int64))),
  read!(io, Array{Complex{Float64},2}(undef, read(io, Int64), read(io, Int64)))
  )

isempty(R::GenResp) = min(isempty(R.desc), isempty(R.resp))
isequal(R1::GenResp, R2::GenResp) = min(isequal(R1.desc, R2.desc), isequal(R1.resp, R2.resp))
==(R1::GenResp, R2::GenResp) = isequal(R1, R2)

hash(R::GenResp) = hash(R.desc, hash(R.resp))

sizeof(R::GenResp) = 16 + sizeof(getfield(R, :desc)) + sizeof(getfield(R, :resp))

@doc """
    PZResp([c = c, p = p, z = z])

Instrument response with three fields. Optionally, fields can be set with keywords at creation.

| F   | Type                      | Meaning
|:--- |:---                       |:----                                      |
| a0  | Float32                   | normalization constant. Equivalencies:    |
|     |                           |  = DSP.jl Type `ZeroPoleGain`, field `:k` |
|     |                           |  = SEED RESP "A0 normalization factor:"   |
|     |                           |  = SEED v2.4 Blockette [53], field 7      |
|     |                           |  != FDSN station XML v1.1                 |
|     |                           |      <Response>                           |
|     |                           |       <InstrumentSensitivity>             |
|     |                           |        <Value>                            |
| f0  | Float32                   | frequency of normalization by a0; NOT     |
|     |                           |   always geophone corner frequency        |
| p   | Array{Complex{Float32},1} | Complex poles of transfer function        |
| z   | Array{Complex{Float32},1} | Complex zeroes of transfer function       |

    PZResp64([c = c, p = p, z = z])

As PZResp, but fields use Float64 precision.

    PZResp(X::Array{Complex{T},2} [, rev=true])

Convert X to a PZResp64 (if `T == Float64`) or PZResp (default) object. Assumes
format X = [p z], i.e., poles are in X[:,1] and zeros in X[:,2]; specify `rev=true`
if the column assignments are X = [z p].

### See Also
resp_a0!, update_resp_a0!, DSP.ZeroPoleGain

### External References
Seed v2.4 manual, http://www.fdsn.org/pdf/SEEDManual_V2.4.pdf
IRIS Resp format, https://ds.iris.edu/ds/nodes/dmc/data/formats/resp/
Julia DSP filter Types, https://juliadsp.github.io/DSP.jl/stable/filters/
""" PZResp
mutable struct PZResp <: InstrumentResponse
  a0::Float32
  f0::Float32
  p::Array{Complex{Float32},1}
  z::Array{Complex{Float32},1}

  function PZResp(  a0::Float32,
                    f0::Float32,
                    p::Array{Complex{Float32},1},
                    z::Array{Complex{Float32},1} )
    return new(a0, f0, p, z)
  end
end

@doc (@doc PZResp)
mutable struct PZResp64 <: InstrumentResponse
  a0::Float64
  f0::Float64
  p::Array{Complex{Float64},1}
  z::Array{Complex{Float64},1}


  function PZResp64(a0::Float64,
                    f0::Float64,
                    p::Array{Complex{Float64},1},
                    z::Array{Complex{Float64},1} )
    return new(a0, f0, p, z)
  end

end

# PZResp default
PZResp( ;
        a0::Float32                    = 1.0f0,
        f0::Float32                    = 1.0f0,
        p::Array{Complex{Float32},1}  = Array{Complex{Float32},1}(undef, 0),
        z::Array{Complex{Float32},1}  = Array{Complex{Float32},1}(undef, 0)
        ) = PZResp(a0, f0, p, z)
PZResp64( ;
          a0::Float64                   = 1.0,
          f0::Float64                   = 1.0,
          p::Array{Complex{Float64},1}  = Array{Complex{Float64},1}(undef, 0),
          z::Array{Complex{Float64},1}  = Array{Complex{Float64},1}(undef, 0)
          ) = PZResp64(a0, f0, p, z)

# How we read from file
PZResp(a0::Float32, f0::Float32, pr::Array{Float32,1}, pi::Array{Float32,1},
  zr::Array{Float32,1}, zi::Array{Float32,1}) = PZResp(a0, f0, complex.(pr, pi), complex.(zr, zi))
PZResp64(a0::Float64, f0::Float64, pr::Array{Float64,1}, pi::Array{Float64,1},
    zr::Array{Float64,1}, zi::Array{Float64,1}) = PZResp64(a0, f0, complex.(pr, pi), complex.(zr, zi))


# Convert from a 2-column complex response
function PZResp(X::Array{Complex{T},2}; rev::Bool=false) where {T <: AbstractFloat}
  @assert size(X,2) == 2
  if rev
    p = X[:,2]
    z = X[:,1]
  else
    p = X[:,1]
    z = X[:,2]
  end
  if T == Float64
    return PZResp64(1.0, 1.0, p, z)
  else
    return PZResp(1.0f0, 1.0f0, p, z)
  end
end

function show(io::IO, Resp::Union{PZResp,PZResp64})
  if get(io, :compact, false) == false
    showresp_full(io, Resp)
  else
    c = :compact => true
    print(io, "a0 = ", repr(getfield(Resp, :a0), context=c), ", ",
              length(getfield(Resp, :z)), " zeros, ",
              length(getfield(Resp, :p)), " poles")
  end
  return nothing
end

function write(io::IO, R::Union{PZResp,PZResp64})
  write(io, R.a0)
  write(io, R.f0)

  p = getfield(R, :p)
  write(io, Int64(lastindex(p)))
  write(io, p)

  z = getfield(R, :z)
  write(io, Int64(lastindex(z)))
  write(io, z)
  return nothing
end

read(io::IO, ::Type{PZResp}) = PZResp(
  read(io, Float32),
  read(io, Float32),
  read!(io, Array{Complex{Float32},1}(undef, read(io, Int64))),
  read!(io, Array{Complex{Float32},1}(undef, read(io, Int64)))
  )

read(io::IO, ::Type{PZResp64}) = PZResp64(
  read(io, Float64),
  read(io, Float64),
  read!(io, Array{Complex{Float64},1}(undef, read(io, Int64))),
  read!(io, Array{Complex{Float64},1}(undef, read(io, Int64)))
  )

isempty(R::Union{PZResp,PZResp64}) = min(
  R.a0 == one(typeof(R.a0)),
  R.f0 == one(typeof(R.f0)),
  isempty(getfield(R, :p)),
  isempty(getfield(R, :z))
  )

function isequal(R1::Union{PZResp,PZResp64}, R2::Union{PZResp,PZResp64})
  q = isequal(getfield(R1, :a0), getfield(R2, :a0))
  if q == true
    q = min(q, isequal(getfield(R1, :f0), getfield(R2, :f0)))
    q = min(q, isequal(getfield(R1, :z), getfield(R2, :z)))
    q = min(q, isequal(getfield(R1, :p), getfield(R2, :p)))
  end
  return q
end
==(R1::Union{PZResp,PZResp64}, R2::Union{PZResp,PZResp64}) = isequal(R1, R2)

function hash(R::Union{PZResp,PZResp64})
  h = hash(R.a0)
  h = hash(R.f0, h)
  h = hash(R.p, h)
  return hash(R.z, h)
end

sizeof(R::Union{PZResp,PZResp64}) = 32 + 2*sizeof(getfield(R, :a0)) + sizeof(getfield(R, :z)) + sizeof(getfield(R, :p))

const flat_resp = PZResp(p = Complex{Float32}[complex(1.0, 1.0)], z = Complex{Float32}[2.0/Complex(1.0, -1.0)])
