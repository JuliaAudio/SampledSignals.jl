VERSION >= v"0.7.0-" && using InteractiveUtils
versioninfo()

if VERSION < v"0.7.0-"
    Pkg.clone(pwd(), "SampledSignals")
    Pkg.build("SampledSignals")
    # for now we need LibSndFile master
    Pkg.add("LibSndFile")
    Pkg.checkout("LibSndFile")
else
    using Pkg
    Pkg.clone(pwd(), "SampledSignals")
    Pkg.build("SampledSignals")
    Pkg.add(PackageSpec(name="LibSndFile", rev="master"))
end
# manually install test dependencies so we can run the test script directly, which avoids
# clobberling our environment
Pkg.add("Compat")
Pkg.add("Unitful")
Pkg.add("FixedPointNumbers")
Pkg.add("FFTW")
Pkg.add("DSP")
Pkg.add("FileIO")
Pkg.add("Gumbo")
