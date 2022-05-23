## Gaussian Process Emulator

A Gaussian process is a type of emulator implemented in `CalibrateEmulateSample.jl`. Gaussian processes
are a generalization of the Gaussian probability distribution, extended to functions rather than random variables.
To build a Gaussian process, we first define a prior over all possible functions. Then we can introduce 
data and narrow down all the possible functions that agree with this data. This gives the posterior over functions.

A useful resource to learn about Gaussian processes is [Rasmussen and Williams (2006)](http://gaussianprocess.org/gpml/).


# Implementation

`CalibrateEmulateSample.jl` allows the Gaussian process emulator to be built using
either [`GaussianProcesses.jl`](https://stor-i.github.io/GaussianProcesses.jl/latest/) 
or [`ScikitLearn.jl`](https://scikitlearnjl.readthedocs.io/en/latest/models/#scikitlearn-models).
To use `GaussianProcesses.jl`, define the package type as
```julia
gppackage = Emulators.GPJL()
```

To use `ScikitLearn.jl`, define the package type as
```julia
gppackage = Emulators.SKLJL()
```


Initialize a basic Gaussian Process with
```julia
gauss_proc = GaussianProcess(
    gppackage)
```

This initializes the prior Gaussian process. To learn the posterior Gaussian process, we combine this with
data which must be provided as a `PairedDataContainer`. You can get this from the output of the EKI step with
`input_output_pairs = Utilities.get_training_points(ekiobj, N_iter)` or you can construct the data manually 
with `input_output_pairs = PairedDataContainer(u, g)` where `u` is are the parameter values and `g` is the model
output. 

We feed this into `Emulator` with
```julia
emulator = Emulator(
    gauss_proc,
    input_output_pairs;
)
optimize_hyperparameters!(emulator)
```
Predictions can then be made using `Emulator.predict(emulator, new_inputs)`.


# Prediction Type

You can specify the type of prediction when initializing the Gaussian Process emulator.
The default type of prediction is to predict data, `YType()`. 
You can create a latent function type prediction with

```julia
gauss_proc = GaussianProcess(
    gppackage,
    prediction_type = FType())

```


# Kernels

The Gaussian process above assumes the default kernel: the Squared Exponential kernel, also called 
the Radial Basis Function (RBF). A different type of kernel can be specified when the Gaussian process 
is initialized. For the `GaussianProcess.jl` package, there are [a range of kernels](https://stor-i.github.io/GaussianProcesses.jl/latest/kernels). 
For example, 
```julia
using GaussianProcesses
my_kernel = GaussianProcesses.Mat32Iso(0., 0.)      # Create a Matern 3/2 kernel with lengthscale=0 and sd=0
gauss_proc = GaussianProcess(
    gppackage;
    kernel = my_kernel )
```
You do not need to provide useful hyperparameter values, these are learned in 
`optimize_hyperparameters!(emulator)`.

You can also combine kernels together through linear operations, for example,
```julia
using GaussianProcesses
kernel_1 = GaussianProcesses.Mat32Iso(0., 0.)      # Create a Matern 3/2 kernel with lengthscale=0 and sd=0
kernel_2 = GaussianProcesses.Lin(0.)               # Create a linear kernel with lengthscale=0
my_kernel = kernel_1 + kernel_2                    # Create a new additive kernel
gauss_proc = GaussianProcess(
    gppackage;
    kernel = my_kernel )
```


# Learning the noise

Often it is useful to learn the noise of the data by adding a white noise kernel. This is added with the 
Boolean keyword `noise_learn` when initializing the Gaussian process. The default is true. 

```julia
gauss_proc = GaussianProcess(
    gppackage;
    noise_learn = true )
```

When `noise_learn` is true, an additional white noise kernel is added to the kernel. The hyperparameters 
of the white noise kernel are learned in `optimize_hyperparameters!(emulator)`. Note that this is done after 
transforming to the decorrelated space (see docs on Emulators).



