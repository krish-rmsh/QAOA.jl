Zygote.@nograd function problem_parameters(local_fields::Vector{Real}, couplings::Matrix{Real})::Vector{Real}
    num_qubits = size(local_fields)[1]
    vcat(2 .* local_fields, [2 * couplings[i, j] for j in 1:num_qubits for i in 1:j-1])
end


function dispatch_parameters(circ, problem::Problem, beta_and_gamma)
    @unpack_Problem problem
    # the number of driver parameters is the number of parameters in the circuit
    # divided by the number of layers, minus the number of problem parameters
    num_driver_parameters = (nparameters(circ) ÷ num_layers) - (num_qubits + num_qubits * (num_qubits - 1) ÷ 2)
    circ = dispatch(circ, reduce(vcat,
                                    [vcat(beta_and_gamma[l + num_layers] .* problem_parameters(local_fields, couplings),
                                          beta_and_gamma[l] .* 2. .* ones(num_driver_parameters)
                                         )
                                    for l in 1:num_layers]
                                )
                   )
    circ
end


Zygote.@nograd function problem_hamiltonian(problem::Problem)
    H =  sum([problem.local_fields[i] * put(i => Z)(problem.num_qubits) for i in 1:problem.num_qubits])
    H += sum([problem.couplings[i, j] * put((i, j) => kron(Z, Z))(problem.num_qubits) for j in 1:problem.num_qubits for i in 1:j-1])
    H
end


"""
    cost_function(problem::Problem, beta_and_gamma::Vector{Float64})

Returns the QAOA cost function, i.e. the expectation value of the problem Hamiltonian.
    
### Input    
- `problem::Problem`: A `Problem` instance defining the optimization problem.
- `beta_and_gamma::Vector{Float64}`: A vector of QAOA parameters.

### Output
- The expectation value of the problem Hamiltonian.

### Notes
This function computes

``
\\langle \\hat H \\rangle = \\left\\langle \\sum_{i=1}^N\\left( h_i \\hat Z_i + \\sum_{j>i} J_{ij}\\hat Z_i \\hat Z_j \\right)\\right\\rangle,
``

where ``N`` is `num_qubits`, ``h_i`` are the `local_fields` and ``J_{ij}`` are the `couplings` from `problem`.
"""    
function cost_function(problem::Problem, beta_and_gamma::Vector{Float64})::Real
    circ = circuit(problem)
    circ = dispatch_parameters(circ, problem, beta_and_gamma)
    reg = apply(uniform_state(nqubits(circ)), circ)
    expect(QAOA.problem_hamiltonian(problem), reg) |> real
end

"""
    optimize_parameters(problem::Problem, beta_and_gamma::Vector{Float64}, algorithm; niter::Int=128)

Gradient-free optimization of the QAOA cost function `using NLopt`.

### Input
- `problem::Problem`: A `Problem` instance defining the optimization problem.
- `beta_and_gamma::Vector{Float64}`: The vector of initial QAOA parameters.
- `algorithm`: One of [NLopt's algorithms](https://nlopt.readthedocs.io/en/latest/NLopt_Algorithms/).
- `niter::Int=128` (optional): Number of optimization steps to be performed.

### Output
- `cost`: Final value of the cost function.
- `params`: The optimized parameters.
- `probabilities`: The simulated probabilities of all possible outcomes.

### Example
- For given number of layers `p`, local fields `h` and couplings `J`, define the problem 

`problem = QAOA.Problem(p, h, J)` 

and then do

`cost, params, probs = QAOA.optimize_parameters(problem, ones(2p), :LN_COBYLA)`.
"""
function optimize_parameters(problem::Problem, beta_and_gamma::Vector{Float64}, algorithm; niter::Int=128)

    opt = Opt(algorithm, 2problem.num_layers)
    opt.lower_bounds = 0.
    # CHANGE BOUNDS?!
    opt.upper_bounds = pi .* vcat([1 for _ in 1:problem.num_layers], [2 for _ in 1:problem.num_layers])
    opt.maxeval = niter
    # opt.xtol_rel = 1e-5
    # opt.xtol_abs = 1e-5

    f = (x, _) -> cost_function(problem, x)

    opt.max_objective = f
    # opt.min_objective = f

    cost, params, info = optimize(opt, beta_and_gamma)

    circ = circuit(problem)
    circ = dispatch_parameters(circ, problem, params)
    probabilities = uniform_state(nqubits(circ)) |> circ |> probs
    cost, params, probabilities
end

"""
    optimize_parameters(problem::Problem, beta_and_gamma::Vector{Float64}; niter::Int=128, learning_rate::Float64 = 0.05)

Gradient optimization of the QAOA cost function `using Zygote`.

### Input
- `problem::Problem`: A `Problem` instance defining the optimization problem.
- `beta_and_gamma::Vector{Float64}`: The vector of initial QAOA parameters.
- `niter::Int=128` (optional): Number of optimization steps to be performed.
- `learning_rate::Float64=0.05` (optional): The learning rate of the gradient-ascent method.
### Output
- `cost`: Final value of the cost function.
- `params`: The optimized parameters.
- `probabilities`: The simulated probabilities of all possible outcomes.

### Notes
- The gradient-ascent method is defined via the parameter update

`params = params .+ learning_rate .* gradient(f, params)[1]`.

### Example
- For given number of layers `p`, local fields `h` and couplings `J`, define the problem 

`problem = QAOA.Problem(p, h, J)` 

and then do

`cost, params, probs = QAOA.optimize_parameters(problem, ones(2p))`.
"""
function optimize_parameters(problem::Problem, beta_and_gamma::Vector{Float64}; niter::Int=128, learning_rate::Float64 = 0.05)

    f = x -> cost_function(problem, x)

    learning_rate = learning_rate
    cost = f(beta_and_gamma)
    params = beta_and_gamma

    for n in 1:niter
        params = params .+ learning_rate .* gradient(f, params)[1]
        cost = f(params)
    end

    circ = circuit(problem)
    circ = dispatch_parameters(circ, problem, params)
    probabilities = uniform_state(nqubits(circ)) |> circ |> probs
    cost, params, probabilities
end



