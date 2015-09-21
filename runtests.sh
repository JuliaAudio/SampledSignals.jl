#!/bin/bash

# Runs the SampleTypes tests including generating an lcov.info file

julia --color=yes --inline=no --code-coverage=user test/runtests.jl
mkdir -p coverage
julia -e 'using Coverage; res=process_folder(); LCOV.writefile("coverage/lcov.info", res); clean_folder(".")'
