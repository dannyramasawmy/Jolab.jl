mutable struct CircularStepIndexModes{T} <: AbstractModes{T}
    r::T
    ncore::T
    na::T
    λ::T
    m::Vector{Int64}
    β::Vector{Complex{T}}
    C::Vector{Complex{T}}
    D::Vector{Complex{T}}
    CircularStepIndexModes{T}(r, ncore, na, λ, m, β, C, D) where T = new{T}(r, ncore, na, λ, m, β, C, D)
end
CircularStepIndexModes(r, ncore, na, λ, m, β, C, D) = CircularStepIndexModes{Float64}(r, ncore, na, λ, m, β, C, D)

mutable struct CircularStepIndexFibre{T} <: AbstractOpticalComponent{T}
    r::T
    ncore::JolabFunction1D{T,Complex{T}}
    na::T
    n₁::JolabFunction1D{T,Complex{T}}
    ref₁::ReferenceFrame{T}
    n₂::JolabFunction1D{T,Complex{T}}
    ref₂::ReferenceFrame{T}
    modes::Vector{CircularStepIndexModes{T}}
    function CircularStepIndexFibre{T}(r, na, ncore, n₁, ref₁, n₂, length) where T
        modes = Vector{CircularStepIndexModes{T}}(undef, 0)
        ref₂ = ReferenceFrame(ref₁.x + length * sin(ref₁.θ) * cos(ref₁.ϕ), ref₁.y + length * sin(ref₁.θ) * sin(ref₁.ϕ), ref₁.z + length * cos(ref₁.θ), ref₁.θ, ref₁.ϕ)
        new{T}(r, ncore, na, n₁, ref₁, n₂, ref₂, modes)
    end
end
CircularStepIndexFibre(r, na, ncore, n₁, ref₁, n₂, length) = CircularStepIndexFibre{Float64}(r, na, ncore, n₁, ref₁, n₂, length)

function rotatestructure!(fib::CircularStepIndexFibre, ref_ref::ReferenceFrame, θ::Real, ϕ::Real)
    rotatereferential!(ref_ref, fib.ref₁, θ, ϕ)
    rotatereferential!(ref_ref, fib.ref₂, θ, ϕ)
end

α1(na, ncore, λ, β) = √((2π / λ * ncore)^2 - β^2)
α2(na, ncore, λ, β) = √(β^2 + (2π / λ)^2 * (na^2 - ncore^2))
nclad(ncore, na) = √(ncore^2 - na^2)

function circularstepindex_modecondition(r::Real, na::Real, ncore::Number, λ::Real, m::Integer, β::Number)::Real
    α_1 = α1(na, ncore, λ, β) # Doesn't work for dispersiveModes
    α_2 = α2(na, ncore, λ, β) # Doens't work for dispersiveModes
    return real(besseljx(m-1, r * α_1) / besseljx(m, r * α_1) + α_2 / α_1 * besselkx(m-1, r * α_2) / besselkx(m, r * α_2))
end

function findmodes!(fibre::CircularStepIndexFibre{T}, λ::Real) where T<:Real
    dispersiveModes = false # can't calculate disperive modes for now
    m = 0;
    sizeA = 10000;
    inc_sizeA = 10000;
    β_A = Vector{Complex{T}}(undef, sizeA)
    m_A = Vector{Int64}(undef, sizeA)
    C_A = Vector{Complex{T}}(undef, sizeA)
    D_A = Vector{Complex{T}}(undef, sizeA)
    modeNumber = 0
    ncore = real(fibre.ncore(λ));
    tmp_nclad = nclad(ncore, fibre.na)
    iWithoutModes = 0;
    while true

        condition(β) = circularstepindex_modecondition(fibre.r, fibre.na, ncore, λ, m, β)

        if m > 0
            α2_min = (1E50 * √(2m / π)) ^(-1/m) * 2m / exp(1) / fibre.r
            βmin = √(α2_min^2 + (2π * (tmp_nclad + @tol) / λ)^2);
        else
            βmin = real(2π / λ * (tmp_nclad + @tol))
        end
        βmax = real(2π / λ * (ncore));

        roots = find_zeros(condition, βmin, βmax, k = 100)
        #(m > 0) && (rootsminus = find_zeros(conditionminus, βmin, βmax))

        (length(roots) == 0) && break
        numberRoots = length(roots)
        for i in 0:(numberRoots-1)
            if modeNumber > sizeA - 2
                resize!(β_A, sizeA + inc_sizeA);
                resize!(m_A, sizeA + inc_sizeA);
                resize!(C_A, sizeA + inc_sizeA);
                resize!(D_A, sizeA + inc_sizeA);
            end

            βᵢ = roots[numberRoots - i]
            # This removes the zeros due to the assymptotas
            if abs(condition(βᵢ)) < 1
                modeNumber += 1;
                m_A[modeNumber] = m
                β_A[modeNumber] = βᵢ
                (C_A[modeNumber], D_A[modeNumber]) = circularstepindex_modeconstant(fibre, λ, m, βᵢ)
            end

            (m == 0) && continue
            βᵢ = roots[numberRoots - i]
            if abs(condition(βᵢ)) < 1
                modeNumber += 1;
                m_A[modeNumber] = -m
                β_A[modeNumber] = βᵢ
                (C_A[modeNumber], D_A[modeNumber]) = circularstepindex_modeconstant(fibre, λ, -m, βᵢ)
            end
        end
        #@show m modeNumber
        m += 1
    end
    resize!(m_A, modeNumber);
    resize!(β_A, modeNumber);
    resize!(C_A, modeNumber);
    resize!(D_A, modeNumber);

    push!(fibre.modes, CircularStepIndexModes{T}(fibre.r, ncore, fibre.na, λ, m_A, β_A, C_A, D_A))
end

function circularstepindex_modeconstant(fibre::CircularStepIndexFibre{T}, λ::Real, m::Integer, β::Number) where {T<:Real}
    lim = 2fibre.r;
    ncore = real(fibre.ncore(λ));
    α_1 = α1(fibre.na, ncore, λ, β);
    α_2 = α2(fibre.na, ncore, λ, β);
    f1(r) = besselj.(m, r .* α_1).^2 .* r;
    (p1, tmp) = hcubature(f1, [0], [fibre.r]; rtol = 1E-8);

    f2(r) = besselk.(m, r .* α_2).^2 .* r;
    (p2, tmp) = hcubature(f2, [fibre.r], [lim]; rtol = 1E-8);

    #c = convert(T, 299792458)
    #μ₀ = convert(T, 0.0000012566370614359172885068872613235)
    #η_1 = 1/2 # c * μ₀ / ncore
    #η_2 = 1/2 #c * μ₀ / nclad(ncore, fibre.na)
    #F = 2π * p1[1] / 2 / η_1 + 2π * p2[1] * besselj(abs(m), fibre.r * α_1)^2 / besselk(abs(m), fibre.r * α_2)^2 / 2 / η_2
    F = 2π * p1[1] + 2π * p2[1] * besselj(m, fibre.r * α_1)^2 / besselk(m, fibre.r * α_2)^2

    C = 1 / √(real(F))
    D = C * besselj(m, fibre.r * α_1) / besselk(m, fibre.r * α_2);
    return (C, D)
end

function circularstepindex_modefield!(e_SXY::AbstractArray{<:Number,3}, r::Real, ncore::Number, na::Real, λ::Real, m::Integer, β::Number, C::Number, D::Number, weigth::Number, x_X::AbstractVector{<:Real}, y_Y::AbstractVector{<:Real}, z=0::Real)

    size(e_SXY, 2) == length(x_X) || error("Wrong sizes");
    size(e_SXY, 3) == length(y_Y) || error("Wrong sizes");
    size(e_SXY, 1) == 1 || error("Wrong sizes")

    α_1 = α1(na, ncore, λ, β);
    α_2 = α2(na, ncore, λ, β);

    iXY = 1;
    @inbounds for iY in eachindex(y_Y)
        for iX in eachindex(x_X)
            r_var = √(x_X[iX]^2 + y_Y[iY]^2);
            ϕ = atan(y_Y[iY], x_X[iX]);
            if (r_var < r)
                e_SXY[iXY] = weigth * C * besselj(m, α_1 * r_var) * exp(im * (m * ϕ + β * z));
            else
                e_SXY[iXY] = weigth * D * besselk(m, α_2 * r_var) * exp(im * (m * ϕ + β * z));
            end
            iXY += 1;
        end
    end
end

function circularstepindex_calculatecoupling!(emodes_A::AbstractArray{Complex{T}}, modes::CircularStepIndexModes{T}, e_SXY::AbstractArray{<:Number,3}, x_X::AbstractVector{<:Real}, y_Y::AbstractVector{<:Real}) where T

    size(e_SXY, 1) == 1 || error("Wrong sizes")
    size(e_SXY, 2) == length(x_X) || error("Wrong sizes")
    size(e_SXY, 3) == length(y_Y) || error("Wrong sizes")

    modeshape_SXY = Array{Complex{T}}(undef, 1, length(x_X), length(y_Y))
    modeshape_XY = reshape(modeshape_SXY, length(x_X), length(y_Y))

    for iMode in eachindex(modes.m)
        circularstepindex_modefield!(modeshape_SXY, modes.r, modes.ncore, modes.na, modes.λ, modes.m[iMode], modes.β[iMode], modes.C[iMode], modes.D[iMode], 1, x_X, y_Y, 0)
        conj!(modeshape_SXY)
        modeshape_SXY .*= e_SXY;

        emodes_A[iMode] = ∫∫(modeshape_XY, x_X, y_Y)
    end
end

@inline function circularstepindex_calculatecoupling(modes::CircularStepIndexModes{T}, e_SXY::AbstractArray{<:Number,3}, x_X::AbstractVector{<:Real}, y_Y::AbstractVector{<:Real}) where T
    emodes_A = Vector{Complex{T}}(undef, length(modes.m))
    circularstepindex_calculatecoupling!(emodes_A, modes, e_SXY, x_X, y_Y)
    return emodes_A
end

function calculatefieldspace(fieldmodes::FieldModes{T}, x_X::AbstractVector{<:Real}, y_Y::AbstractArray{<:Real}) where T<:Real
    modesNumber = length(fieldmodes.modes.m);
    e_SXY = zeros(Complex{T}, length(x_X) * length(y_Y));
    tmp_e_SXY = Array{Complex{T}, 3}(undef, 1, length(x_X), length(y_Y));
    for i in 1:modesNumber
       circularstepindex_modefield!(tmp_e_SXY, fieldmodes.modes.r, fieldmodes.modes.ncore, fieldmodes.modes.na, fieldmodes.modes.λ, fieldmodes.modes.m[i], fieldmodes.modes.β[i], fieldmodes.modes.C[i], fieldmodes.modes.D[i], fieldmodes.modesamplitude[i], x_X, y_Y, 0)
       e_SXY .+= vec(tmp_e_SXY);
    end
    e_SXY = reshape(e_SXY, 1, length(x_X), length(y_Y))
end

function lightinteraction(fibre::CircularStepIndexFibre{T}, fieldspace::FieldSpace) where T
    reffib = fieldspace.dir > 0 ? fibre.ref₁ : fibre.ref₂

    changereferential!(fieldspace, reffib);

    modeArg = -1
    @inbounds for i in eachindex(fibre.modes)
        (abs(fibre.modes[i].λ - fieldspace.λ) < @tol) && (modeArg = i; break)
    end
    if modeArg == -1
        findmodes!(fibre, fieldspace.λ)
        modeArg = length(fibre.modes)
    end

    modesamplitude = circularstepindex_calculatecoupling(fibre.modes[modeArg], fieldspace.e_SXY, fieldspace.x_X, fieldspace.y_Y);
    modesfield = FieldModes{T}(modesamplitude, fibre.modes[modeArg], fieldspace.dir, fieldspace.ref);
end

function lightinteraction(fibre::CircularStepIndexFibre{A}, fieldmodes::FieldModes{T}, x_X::AbstractVector{<:Real}, y_Y::AbstractVector{<:Real}) where {T<:Real,A}
    fieldmodes.dir > 0 ? ref = fibre.ref₂ : ref = fibre.ref₁

    changereferential!(fieldmodes, ref);
    e_SXY = calculatefieldspace(fieldmodes, x_X, y_Y);

    n = fieldmodes.dir > 0 ? fibre.n₂(fieldmodes.modes.λ) : fibre.n₁(fieldmodes.modes.λ)
    return FieldSpace{T}(x_X, y_Y, e_SXY, fieldmodes.modes.λ, n, fieldmodes.dir, ref)
end

function refractiveindex_distribution(modes::CircularStepIndexModes{T}) where T
    n(x,y) = (x^2 + y^2) < modes.r^2 ? modes.ncore : nclad(modes.ncore, modes.na)
    return JolabFunction2D{T,Complex{T}}(n)
end

function Base.getindex(modes::CircularStepIndexModes{T}, i) where T
    return CircularStepIndexModes{T}(modes.r, modes.ncore, modes.na, modes.λ, [modes.m[i]], [modes.β[i]], [modes.C[i]], [modes.D[i]])
end
Base.lastindex(modes::CircularStepIndexModes{T}) where T = numberofmodes(modes)
numberofmodes(modes::CircularStepIndexModes{T}) where T = length(modes.m)
