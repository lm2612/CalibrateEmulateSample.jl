## Gaussian Process Emulator

A Gaussian process is a type of emulator implemented in `CalibrateEmulateSample.jl`. Gaussian processes
are a generalization of the Gaussian probability distribution, extended to functions rather than random variables.
To build a Gaussian process, we first define a prior over all possible functions. Then we can introduce 
data and narrow down all the possible functions that agree with this data. This gives the posterior over functions.

A good resource to learn about Gaussian processes is [Rasmussen and Williams, (2006)](http://gaussianprocess.org/gpml/).


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
data in the form of 
```julia
input_output_pairs = PairedDataContainer(u, g)
```

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

The Gaussian process above assumes the default kernel: the Squared Exponential kernel, also called the Radial Basis Function (RBF).
A different type of kernel can be specified when the Gaussian process is initialized. `GaussianProcess.jl` provides [a wide range of kernels
](https://stor-i.github.io/GaussianProcesses.jl/latest/kernels).
You can choose a different kernel with
```julia
gauss_proc = GaussianProcess(
    gppackage;
    kernel = )
```
You can also combine kernels 


# Learning the noise
Often it is useful to learn the noise of the data 


```julia
gauss_proc = GaussianProcess(
    gppackage;
    learn_noise = true )
```

