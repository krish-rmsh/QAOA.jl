module QAOA

using Yao, YaoBlocks, Zygote
using Parameters
using NLopt
using PyCall
using DocStringExtensions

include("problem.jl")
export Problem

include("optimization.jl")
export cost_function, optimize_parameters

include("utils.jl")
export sherrington_kirkpatrick, partition_problem, max_cut, min_vertex_cover

include("circuit.jl")

end