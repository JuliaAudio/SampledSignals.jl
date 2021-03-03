using InteractiveUtils
versioninfo()

using Pkg
Pkg.clone(pwd(), "SampledSignals")
Pkg.build("SampledSignals")
Pkg.add(PackageSpec(name="LibSndFile", rev="master"))

# manually install test dependencies so we can run the test script directly, which avoids
# clobberling our environment
Pkg.add("Unitful")
Pkg.add("FixedPointNumbers")
Pkg.add("FFTW")
Pkg.add("DSP")
Pkg.add("FileIO")
Pkg.add("Gumbo")
