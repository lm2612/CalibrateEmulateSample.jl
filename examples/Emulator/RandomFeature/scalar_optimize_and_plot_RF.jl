# Reference the in-tree version of CalibrateEmulateSample on Julias load path
include(joinpath(@__DIR__, "..", "..", "ci", "linkfig.jl"))

# Import modules
using Random
using StableRNGs
using Distributions
using Statistics
using LinearAlgebra
using CalibrateEmulateSample.Emulators
using CalibrateEmulateSample.DataContainers
using CalibrateEmulateSample.ParameterDistributions
using CalibrateEmulateSample.EnsembleKalmanProcesses


case = "scalar"
println("running case $case")
kernel_structure = SeparableKernel(LowRankFactor(2, 1e-8), OneDimFactor()) # input and output(1D) cov structure in sep kernel
plot_flag = true
if plot_flag
    ENV["GKSwstype"] = "100"
    using Plots
    gr(size = (1500, 700))
    #    Plots.scalefontsizes(1.3) # scales on recursive calls to include..
    font = Plots.font("Helvetica", 18)
    fontdict = Dict(:guidefont => font, :xtickfont => font, :ytickfont => font, :legendfont => font)

end

function meshgrid(vx::AbstractVector{T}, vy::AbstractVector{T}) where {T}
    m, n = length(vy), length(vx)
    gx = reshape(repeat(vx, inner = m, outer = 1), m, n)
    gy = reshape(repeat(vy, inner = 1, outer = n), m, n)

    return gx, gy
end

function main()

    rng_seed = 41
    Random.seed!(rng_seed)
    output_directory = joinpath(@__DIR__, "output")
    if !isdir(output_directory)
        mkdir(output_directory)
    end



    #problem
    n = 150  # number of training points
    p = 2   # input dim 
    d = 2   # output dim
    X = 2.0 * π * rand(p, n)
    # G(x1, x2)
    g1x = sin.(X[1, :]) .+ cos.(X[2, :])
    g2x = sin.(X[1, :]) .- cos.(X[2, :])
    gx = zeros(2, n)
    gx[1, :] = g1x
    gx[2, :] = g2x

    # Add noise η
    μ = zeros(d)
    Σ = 0.1 * [[0.8, 0.1] [0.1, 0.5]] # d x d
    noise_samples = rand(MvNormal(μ, Σ), n)
    # y = G(x) + η
    Y = gx .+ noise_samples

    iopairs = PairedDataContainer(X, Y, data_are_columns = true)
    @assert get_inputs(iopairs) == X
    @assert get_outputs(iopairs) == Y

    #plot training data with and without noise
    if plot_flag
        p1 = plot(
            X[1, :],
            X[2, :],
            g1x,
            st = :surface,
            camera = (30, 60),
            c = :cividis,
            xlabel = "x1",
            ylabel = "x2",
            zguidefontrotation = 90,
        )

        figpath = joinpath(output_directory, "RF_observed_y1nonoise.png")
        savefig(figpath)

        p2 = plot(
            X[1, :],
            X[2, :],
            g2x,
            st = :surface,
            camera = (30, 60),
            c = :cividis,
            xlabel = "x1",
            ylabel = "x2",
            zguidefontrotation = 90,
        )
        figpath = joinpath(output_directory, "RF_observed_y2nonoise.png")
        savefig(figpath)

        p3 = plot(
            X[1, :],
            X[2, :],
            Y[1, :],
            st = :surface,
            camera = (30, 60),
            c = :cividis,
            xlabel = "x1",
            ylabel = "x2",
            zguidefontrotation = 90,
        )
        figpath = joinpath(output_directory, "RF_observed_y1.png")
        savefig(figpath)

        p4 = plot(
            X[1, :],
            X[2, :],
            Y[2, :],
            st = :surface,
            camera = (30, 60),
            c = :cividis,
            xlabel = "x1",
            ylabel = "x2",
            zguidefontrotation = 90,
        )
        figpath = joinpath(output_directory, "RF_observed_y2.png")
        savefig(figpath)

    end

    # setup random features
    n_features = 400
    optimizer_options = Dict(
        "n_iteration" => 20,
        "n_ensemble" => 20,
        "verbose" => true,
        "scheduler" => DataMisfitController(terminate_at = 100.0),
    ) #"Max" iterations (may do less)


    srfi = ScalarRandomFeatureInterface(
        n_features,
        p,
        kernel_structure = kernel_structure,
        optimizer_options = optimizer_options,
    )
    emulator = Emulator(srfi, iopairs, obs_noise_cov = Σ, normalize_inputs = true)
    println("build RF with $n training points and $(n_features) random features.")

    optimize_hyperparameters!(emulator) # although RF already optimized

    # Plot mean and variance of the predicted observables y1 and y2
    # For this, we generate test points on a x1-x2 grid.
    n_pts = 200
    x1 = range(0.0, stop = 4.0 / 5.0 * 2 * π, length = n_pts)
    x2 = range(0.0, stop = 4.0 / 5.0 * 2 * π, length = n_pts)
    X1, X2 = meshgrid(x1, x2)
    # Input for predict has to be of size N_samples x input_dim
    inputs = permutedims(hcat(X1[:], X2[:]), (2, 1))

    rf_mean, rf_cov = predict(emulator, inputs, transform_to_real = true)
    println("end predictions at ", n_pts * n_pts, " points")


    #plot predictions
    for y_i in 1:d
        rf_var_temp = [diag(rf_cov[j]) for j in 1:length(rf_cov)] # (40000,)
        rf_var = permutedims(reduce(vcat, [x' for x in rf_var_temp]), (2, 1)) # 2 x 40000

        mean_grid = reshape(rf_mean[y_i, :], n_pts, n_pts) # 2 x 40000
        if plot_flag
            p5 = plot(
                x1,
                x2,
                mean_grid,
                st = :surface,
                camera = (30, 60),
                c = :cividis,
                xlabel = "x1",
                ylabel = "x2",
                zlabel = "mean of y" * string(y_i),
                zguidefontrotation = 90,
            )
        end
        var_grid = reshape(rf_var[y_i, :], n_pts, n_pts)
        if plot_flag
            p6 = plot(
                x1,
                x2,
                var_grid,
                st = :surface,
                camera = (30, 60),
                c = :cividis,
                xlabel = "x1",
                ylabel = "x2",
                zlabel = "var of y" * string(y_i),
                zguidefontrotation = 90,
            )

            plot(p5, p6, layout = (1, 2), legend = false)

            savefig(joinpath(output_directory, "RF_" * case * "_y" * string(y_i) * "_predictions.png"))
        end
    end

    # Plot the true components of G(x1, x2)
    g1_true = sin.(inputs[1, :]) .+ cos.(inputs[2, :])
    g1_true_grid = reshape(g1_true, n_pts, n_pts)
    if plot_flag
        p7 = plot(
            x1,
            x2,
            g1_true_grid,
            st = :surface,
            camera = (30, 60),
            c = :cividis,
            xlabel = "x1",
            ylabel = "x2",
            zlabel = "sin(x1) + cos(x2)",
            zguidefontrotation = 90,
        )
        savefig(joinpath(output_directory, "RF_" * case * "_true_g1.png"))
    end

    g2_true = sin.(inputs[1, :]) .- cos.(inputs[2, :])
    g2_true_grid = reshape(g2_true, n_pts, n_pts)
    if plot_flag
        p8 = plot(
            x1,
            x2,
            g2_true_grid,
            st = :surface,
            camera = (30, 60),
            c = :cividis,
            xlabel = "x1",
            ylabel = "x2",
            zlabel = "sin(x1) - cos(x2)",
            zguidefontrotation = 90,
        )
        g_true_grids = [g1_true_grid, g2_true_grid]

        savefig(joinpath(output_directory, "RF_" * case * "_true_g2.png"))

    end

    # Plot the difference between the truth and the mean of the predictions
    for y_i in 1:d

        # Reshape rf_cov to size N_samples x output_dim
        rf_var_temp = [diag(rf_cov[j]) for j in 1:length(rf_cov)] # (40000,)
        rf_var = permutedims(vcat([x' for x in rf_var_temp]...), (2, 1)) # 40000 x 2

        mean_grid = reshape(rf_mean[y_i, :], n_pts, n_pts)
        var_grid = reshape(rf_var[y_i, :], n_pts, n_pts)
        # Compute and plot 1/variance * (truth - prediction)^2

        if plot_flag
            zlabel = "1/var * (true_y" * string(y_i) * " - predicted_y" * string(y_i) * ")^2"

            p9 = plot(
                x1,
                x2,
                sqrt.(1.0 ./ var_grid .* (g_true_grids[y_i] .- mean_grid) .^ 2),
                st = :surface,
                camera = (30, 60),
                c = :magma,
                zlabel = zlabel,
                xlabel = "x1",
                ylabel = "x2",
                zguidefontrotation = 90,
            )

            savefig(joinpath(output_directory, "RF_" * case * "_y" * string(y_i) * "_difference_truth_prediction.png"))
        end
    end
end

main()
