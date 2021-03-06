function lightinteraction(comp::AbstractOpticalComponent, fieldi::AbstractFieldMonochromatic) where T
    coef = coefficient_specific(comp, fieldi)
    return lightinteraction(coef, fieldi)
end

function coefficient_specific(comps::AbstractVector{<:AbstractOpticalComponent{T}}, fieldi::AbstractFieldMonochromatic) where T
    coefs = Vector{AbstractCoefficient{T}}(undef, length(comps))
    fieldaux = fieldi

    if dir(fieldi) > 0
        for i in eachindex(comps)
            coefs[i] = coefficient_specific(comps[i], fieldaux)
            (tmp, fieldaux) = getfields_lr(coefs[i])
        end
    else
        sizeA = length(comps)
        for i in eachindex(comps)
            coefs[sizeA - i + 1] = coefficient_specific(comps[sizeA-i + 1], fieldaux)
            (fieldaux, tmp) = getfields_lr(coefs[sizeA-i+1])
        end
    end
	return coefs
end

function lightinteraction(comps::AbstractVector{<:AbstractOpticalComponent{T}}, fieldi::AbstractFieldMonochromatic) where T
    coefs = coefficient_general(comps, fieldi)
    return lightinteraction(coefs, fieldi)
end

rotatestructure!(comp::AbstractOpticalComponent, ref_ref::ReferenceFrame, θ::Real, ϕ::Real) = rotatereferenceframe!(ref_ref, comp.ref, θ, ϕ)
function rotatestructure(comp::AbstractOpticalComponent, ref_ref::ReferenceFrame, θ::Real, ϕ::Real)
	aux = deepcopy(comp)
	rotatestructure!(aux, ref_ref, θ, ϕ)
	return aux
end

translatestructure!(comp::AbstractOpticalComponent, x::Real, y::Real, z::Real) = translatereferenceframe!(comp.ref, x, y, z)
function translatestructure(comp::AbstractOpticalComponent, x::Real, y::Real, z::Real)
	aux = deepcopy(comp)
	translatestructure!(aux, x, y, z)
	return aux
end

function rotatestructure(comps::AbstractVector{T}, ref_ref::ReferenceFrame, θ::Real, ϕ::Real) where {T<:AbstractOpticalComponent}
	out = Vector{T}(undef, length(comps))
	@inbounds for i in eachindex(comps)
		out[i] = rotatestructure(comps[i], ref_ref, θ, ϕ)
	end
	return out
end

function translatestructure(comps::AbstractVector{T}, x::Real, y::Real, z::Real) where {T<:AbstractOpticalComponent}
	out = Vector{T}(undef, length(comps))
	@inbounds for i in eachindex(comps)
		out[i] = translatestructure(comps[i], x, y, z)
	end
	return out
end

function coefficient_general(comps::AbstractVector{<:AbstractOpticalComponent{T}}, fieldi::AbstractFieldMonochromatic) where T
    coef = Vector{ScatteringMatrix{T}}(undef, 2)
    if dir(fieldi) > 0
		coef[1] = coefficient_general(comps[1], fieldi)
        for i in 2:length(comps)
            coef[2] = coefficient_general(comps[i], coef[1].fieldr)
			coef[1] = coefficient_general(coef)
        end
		return coef[1]
    else
        sizeA = length(comps)
		coef[2] = coefficient_general(comps[sizeA], fieldi)
        for i in 1:length(comps)-1
            coef[1] = coefficient_general(comps[sizeA-i],coef[2].fieldl)
            coef[2] = coefficient_general(coef)
        end
		return coef[2]
    end
end

ref1(comp::AbstractOpticalComponent) = comp.ref
ref2(comp::AbstractOpticalComponent) = comp.ref
