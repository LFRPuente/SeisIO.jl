function read_asdf!(S::GphysData, hdf::String, id::Union{String,Regex}, s::TimeSpec, t::TimeSpec, msr::Bool, v::Int64)

  SX = SeisData() # for XML
  idr = isa(id, String) ? id_to_regex(id) : id

  if typeof(s) == String && typeof(t) == String
    d0 = s
    d1 = t
    ts = DateTime(s).instant.periods.value*1000 - dtconst
    te = DateTime(t).instant.periods.value*1000 - dtconst
  else
    (d0, d1) = parsetimewin(s, t)
    ts = DateTime(d0).instant.periods.value*1000 - dtconst
    te = DateTime(d1).instant.periods.value*1000 - dtconst
  end
  ts *= 1000
  te *= 1000
  Δ = 0
  fs = 0.0

  # this nesting is a mess
  netsta = netsta_to_regex(id)
  idr = id_to_regex(id)
  f = h5open(hdf, "r")
  W = f["Waveforms"]
  A = names(W)
  sort!(A)

  for i in A
    if occursin(netsta, i)
      w = W[i]
      N = names(w)
      sort!(N)
      for n in N
        if n == "StationXML"
          sxml = String(UInt8.(read(w[n])))
          read_station_xml!(SX, sxml, msr=msr, noappend=false, s=s, t=t, v=v)
        elseif occursin(idr, n)
          x = w[n]
          nx = length(x)
          t0 = read(x["starttime"])
          fs = read(x["sampling_rate"])

          # convert fs to sampling interval in ns
          Δ = round(Int64, 1.0e9/fs)
          t1 = t0 + nx*Δ

          if (ts ≤ t1) && (te ≥ t0)
            i0, i1, t2 = get_trace_bounds(ts, te, t0, t1, Δ, nx)
            ni = i1-i0+1
            trace_start = div(t0 + Δ*(i0-1), 1000)
            trace_end = div(t0 + Δ*(i1-1), 1000)

            cid = String(split(n, "_", limit=2, keepempty=true)[1])
            j = findid(cid, S.id)
            if j == 0
              T = eltype(x)
              nX = div(te-ts, Δ)
              push!(S, SeisChannel(id = cid,
                                   fs = fs,
                                   x = Array{T,1}(undef, nX)))
              j = S.n
              nt = 2
              ct = Array{Int64, 2}(undef, 2, 2)
              setindex!(ct, one(Int64), 1)
              setindex!(ct, ni, 2)
              setindex!(ct, div(t2, 1000), 3)
              setindex!(ct, zero(Int64), 4)
              setindex!(getfield(S, :t), ct, j)
              si = 1
              ei = ni
            else
              ct = getindex(getfield(S, :t), j)
              nt = div(lastindex(ct), 2)
              L = lastindex(S.x[j])
              if nt > 0
                xi = getindex(ct, nt)
                te = endtime(ct, getindex(getfield(S, :fs), j))
              end
              if xi + ni > L
                resize!(S.x[j], xi + max(ni, nX))
              end
              check_for_gap!(S, j, div(t2, 1000), ni, v)
              si = xi+1
              ei = si+ni-1
            end

            X = S.x[j]
            load_data!(X, x, i0:i1, si:ei)
          end
        end
      end
    end
  end

  # Ensure data source is logged accurately
  fill!(S.src, hdf)

  # merge in the XML that we read
  sxml_mergehdr!(S, SX, noappend=true, nofs=true, s=s, t=t, v=v)

  trunc_x!(S)

  # Done
  return S
end

function read_asdf(hdf::String, id::Union{String,Regex}, s::TimeSpec, t::TimeSpec, msr::Bool, v::Int64)
  S = SeisData()
  read_asdf!(S, hdf, id, s, t, msr, v)
  return S
end