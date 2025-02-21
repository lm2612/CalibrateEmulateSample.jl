using OrdinaryDiffEq
using Random, Distributions, LinearAlgebra
ENV["GKSwstype"] = "100"
using CairoMakie, ColorSchemes #for plots
using JLD2

# CES 
using CalibrateEmulateSample
using CalibrateEmulateSample.Emulators
using CalibrateEmulateSample.ParameterDistributions
using CalibrateEmulateSample.EnsembleKalmanProcesses
using CalibrateEmulateSample.DataContainers
EKP = CalibrateEmulateSample.EnsembleKalmanProcesses


function lorenz(du, u, p, t)
    du[1] = 10.0 * (u[2] - u[1])
    du[2] = u[1] * (28.0 - u[3]) - u[2]
    du[3] = u[1] * u[2] - (8 / 3) * u[3]
end

function main()

    # rng
    rng = MersenneTwister(1232434)

    n_repeats = 1 # repeat exp with same data.
    println("run experiment $n_repeats times")

    # Run L63 from 0 -> tmax
    u0 = [1.0; 0.0; 0.0]
    tmax = 20
    dt = 0.01
    tspan = (0.0, tmax)
    prob = ODEProblem(lorenz, u0, tspan)
    sol = solve(prob, Euler(), dt = dt)

    # Run L63 from end for test trajetory data
    tmax_test = 100
    tspan_test = (0.0, tmax_test)
    u0_test = sol.u[end]
    prob_test = ODEProblem(lorenz, u0_test, tspan_test)
    sol_test = solve(prob_test, Euler(), dt = dt)

    # Run L63 from end for histogram matching data
    tmax_hist = 1000
    tspan_hist = (0.0, tmax_hist)
    u0_hist = sol_test.u[end]
    prob_hist = ODEProblem(lorenz, u0_hist, tspan_hist)
    sol_hist = solve(prob_hist, Euler(), dt = dt)


    # test data for plotting
    xspan_test = 0.0:dt:tmax_test
    solplot = zeros(3, length(xspan_test))
    for i in 1:length(xspan_test)
        solplot[:, i] = sol_test.u[i] #noiseless
    end

    # hist data for plotting
    xspan_hist = 0.0:dt:tmax_hist
    solhist = zeros(3, length(xspan_hist))
    for i in 1:length(xspan_hist)
        solhist[:, i] = sol_hist.u[i] #noiseless
    end

    # Create training pairs (with noise) from subsampling [burnin,tmax] 
    tburn = 1 # NB works better with no spin-up!
    burnin = Int(floor(tburn / dt))
    n_train_pts = 600 #600 
    sample_rand = true
    if sample_rand
        ind = Int.(shuffle!(rng, Vector(burnin:(tmax / dt - 1)))[1:n_train_pts])
    else
        ind = burnin:(n_train_pts + burnin)
    end
    n_tp = length(ind)
    input = zeros(3, n_tp)
    output = zeros(3, n_tp)
    Γy = 1e-4 * I(3)
    noise = rand(rng, MvNormal(zeros(3), Γy), n_tp)
    for i in 1:n_tp
        input[:, i] = sol.u[ind[i]]
        output[:, i] = sol.u[ind[i] + 1] + noise[:, i]
    end
    iopairs = PairedDataContainer(input, output)


    # Emulate
    cases =
        ["GP", "RF-scalar", "RF-scalar-diagin", "RF-vector-svd-nonsep", "RF-vector-nosvd-nonsep", "RF-vector-nosvd-sep"]

    case = cases[5]
    decorrelate = true
    nugget = Float64(1e-12)
    u_test = []
    u_hist = []
    train_err = []
    for rep_idx in 1:n_repeats

        overrides = Dict(
            "verbose" => true,
            "scheduler" => DataMisfitController(terminate_at = 1e4),
            "cov_sample_multiplier" => 0.5,
            "n_features_opt" => 200,
            "n_iteration" => 20,
            "accelerator" => NesterovAccelerator(),
        )

        # Build ML tools
        if case == "GP"
            gppackage = Emulators.GPJL()
            pred_type = Emulators.YType()
            mlt = GaussianProcess(
                gppackage;
                kernel = nothing, # use default squared exponential kernel
                prediction_type = pred_type,
                noise_learn = false,
            )

        elseif case ∈ ["RF-scalar", "RF-scalar-diagin"]
            n_features = 10 * Int(floor(sqrt(3 * n_tp)))
            kernel_structure =
                case == "RF-scalar-diagin" ? SeparableKernel(DiagonalFactor(nugget), OneDimFactor()) :
                SeparableKernel(LowRankFactor(3, nugget), OneDimFactor())
            mlt = ScalarRandomFeatureInterface(
                n_features,
                3,
                rng = rng,
                kernel_structure = kernel_structure,
                optimizer_options = overrides,
            )
        elseif case ∈ ["RF-vector-svd-nonsep"]
            kernel_structure = NonseparableKernel(LowRankFactor(6, nugget))
            n_features = 500

            mlt = VectorRandomFeatureInterface(
                n_features,
                3,
                3,
                rng = rng,
                kernel_structure = kernel_structure,
                optimizer_options = overrides,
            )
        elseif case ∈ ["RF-vector-nosvd-nonsep"]
            kernel_structure = NonseparableKernel(LowRankFactor(3, nugget))
            n_features = 500
            decorrelate = false # don't do SVD
            mlt = VectorRandomFeatureInterface(
                n_features,
                3,
                3,
                rng = rng,
                kernel_structure = kernel_structure,
                optimizer_options = overrides,
            )
        elseif case ∈ ["RF-vector-nosvd-sep"]
            kernel_structure = SeparableKernel(LowRankFactor(3, nugget), LowRankFactor(3, nugget))
            n_features = 500
            decorrelate = false # don't do SVD
            mlt = VectorRandomFeatureInterface(
                n_features,
                3,
                3,
                rng = rng,
                kernel_structure = kernel_structure,
                optimizer_options = overrides,
            )
        end

        # Emulate
        emulator = Emulator(mlt, iopairs; obs_noise_cov = Γy, decorrelate = decorrelate)
        optimize_hyperparameters!(emulator)


        # Predict with emulator
        u_test_tmp = zeros(3, length(xspan_test))
        u_test_tmp[:, 1] = sol_test.u[1]

        for i in 1:(length(xspan_test) - 1)
            rf_mean, _ = predict(emulator, u_test_tmp[:, i:i], transform_to_real = true) # 3x1 matrix
            u_test_tmp[:, i + 1] = rf_mean
        end

        train_err_tmp = [0.0]
        for i in 1:size(input, 2)
            train_mean, _ = predict(emulator, input[:, i:i], transform_to_real = true) # 3x1
            train_err_tmp[1] += norm(train_mean - output[:, i])
        end
        println("normalized L^2 error on training data:", 1 / size(input, 2) * train_err_tmp[1])

        u_hist_tmp = zeros(3, length(xspan_hist))
        u_hist_tmp[:, 1] = sol_hist.u[1]  # start at end of previous sim

        for i in 1:(length(xspan_hist) - 1)
            rf_mean, _ = predict(emulator, u_hist_tmp[:, i:i], transform_to_real = true) # 3x1 matrix
            u_hist_tmp[:, i + 1] = rf_mean
        end

        push!(train_err, train_err_tmp)
        push!(u_test, u_test_tmp)
        push!(u_hist, u_hist_tmp)

        # plots for the first repeat
        if rep_idx == 1
            # plotting trace
            f = Figure(resolution = (900, 450))
            axx = Axis(f[1, 1], xlabel = "time", ylabel = "x")
            axy = Axis(f[2, 1], xlabel = "time", ylabel = "y")
            axz = Axis(f[3, 1], xlabel = "time", ylabel = "z")

            xx = 0:dt:tmax_test
            lines!(axx, xx, u_test_tmp[1, :], color = :blue)
            lines!(axy, xx, u_test_tmp[2, :], color = :blue)
            lines!(axz, xx, u_test_tmp[3, :], color = :blue)

            lines!(axx, xspan_test, solplot[1, :], color = :orange)
            lines!(axy, xspan_test, solplot[2, :], color = :orange)
            lines!(axz, xspan_test, solplot[3, :], color = :orange)

            current_figure()
            # save
            save("l63_test.png", f, px_per_unit = 3)
            save("l63_test.pdf", f, pt_per_unit = 3)

            # plot attractor
            f3 = Figure()
            lines(f3[1, 1], u_test_tmp[1, :], u_test_tmp[3, :], color = :blue)
            lines(f3[2, 1], solplot[1, :], solplot[3, :], color = :orange)

            # save
            save("l63_attr.png", f3, px_per_unit = 3)
            save("l63_attr.pdf", f3, pt_per_unit = 3)

            # plotting histograms
            f2 = Figure()
            hist(f2[1, 1], u_hist_tmp[1, :], bins = 50, normalization = :pdf, color = (:blue, 0.5))
            hist(f2[1, 2], u_hist_tmp[2, :], bins = 50, normalization = :pdf, color = (:blue, 0.5))
            hist(f2[1, 3], u_hist_tmp[3, :], bins = 50, normalization = :pdf, color = (:blue, 0.5))

            hist!(f2[1, 1], solhist[1, :], bins = 50, normalization = :pdf, color = (:orange, 0.5))
            hist!(f2[1, 2], solhist[2, :], bins = 50, normalization = :pdf, color = (:orange, 0.5))
            hist!(f2[1, 3], solhist[3, :], bins = 50, normalization = :pdf, color = (:orange, 0.5))

            # save
            save("l63_pdf.png", f2, px_per_unit = 3)
            save("l63_pdf.pdf", f2, pt_per_unit = 3)
        end

    end

    # save data
    JLD2.save("l63_trainerr.jld2", "train_err", train_err)
    JLD2.save("l63_histdata.jld2", "solhist", solhist, "uhist", u_hist)
    JLD2.save("l63_testdata.jld2", "solplot", solplot, "uplot", u_test)

    # compare  marginal histograms to truth - rough measure of fit
    sol_cdf = sort(solhist, dims = 2)

    u_cdf = []
    for u in u_hist
        u_cdf_tmp = sort(u, dims = 2)
        push!(u_cdf, u_cdf_tmp)
    end

    f4 = Figure(resolution = (900, Int(floor(900 / 1.618))))
    axx = Axis(f4[1, 1], xlabel = "", ylabel = "x")
    axy = Axis(f4[1, 2], xlabel = "", ylabel = "y")
    axz = Axis(f4[1, 3], xlabel = "", ylabel = "z")

    unif_samples = (1:size(sol_cdf, 2)) / size(sol_cdf, 2)

    for u in u_cdf
        lines!(axx, u[1, :], unif_samples, color = (:blue, 0.2), linewidth = 4)
        lines!(axy, u[2, :], unif_samples, color = (:blue, 0.2), linewidth = 4)
        lines!(axz, u[3, :], unif_samples, color = (:blue, 0.2), linewidth = 4)
    end

    lines!(axx, sol_cdf[1, :], unif_samples, color = (:orange, 1.0), linewidth = 4)
    lines!(axy, sol_cdf[2, :], unif_samples, color = (:orange, 1.0), linewidth = 4)
    lines!(axz, sol_cdf[3, :], unif_samples, color = (:orange, 1.0), linewidth = 4)



    # save
    save("l63_cdfs.png", f4, px_per_unit = 3)
    save("l63_cdfs.pdf", f4, pt_per_unit = 3)

end

main()
