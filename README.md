# BuildFS

`BuildFS` is a dynamic approach for detecting faults in parallel
and incremental builds.
Our method is based on a model (`BuildFS`) that treats a build execution
stemming from an arbitrary build system as a sequence of tasks, where each task
receives a set of input files, performs a number of file system operations,
and finally produces a number of output files.
`BuildFS` stakes into account
(1) the specification (as declared in build scripts)
and (2) the definition (as observed during a build through file accesses)
of each build task.
By combining the two elements,
we formally define three different types of faults related to
incremental and parallel builds that
arise when a file access violates the specification of build.
Our testing approach operates as follows.
First, it monitors the execution of an instrumented build script,
and models this execution in `BuildFS`.
Our method then verifies the correctness of the build execution
by ensuring that there is no file access that leads to
any fault concerning incrementality or parallelism.
Note that to uncover faults, our method only requires a single full build.


## Building

Fetch the repo by running

````
git clone --recursive https://github.com/theosotr/buildfs
````


### Build Docker Images

To build a Docker image that contains
an environment for executing and analyzing build executions
through `BuildFS`, run

```bash
docker build -t buildfs --build-arg IMAGE_NAME=<base-image> .
```

where `<base-image>` is the base Docker used to set up
the environment. We have tested our Docker script
on `ubuntu:18.04` and `debian:stable` base images.

### Building from source

To build `BuildFS` from source, you have to
install some necessary packages first

```bash
apt install opam m4
```

Then, install OCaml compiler 4.07 by running

```bash
opam init -y
eval `opam config env`
opam switch 4.07.0
```

Next, install some opam packages used by `BuildFS`

```bash
eval `opam config env`
opam install -y ppx_jane core yojson dune fd-send-recv fpath
```

Finally, build `BuildFS` by running

```bash
make
sudo make install
```

This will build the `buildfs` executable and install
the scripts for instrumenting Make and Gradle builds
into the `/usr/local/bin` path.

## Use BuildFS as standalone tool

Here, we describe how you can use `BuildFS`
as a standalone tool (without employing a Docker image).
Currently, `BuildFS` has support for two well-established
and popular build systems (namely, GNU Make and Gradle).

### Make Builds


You have analyze and test your Make builds by simply running
the following command
from the directory where your `Makefile` is located.

```
buildfs make-build -mode online
```

The command above executes your build,
and analyzes its execution.
It reports any missing inputs or ordering violations,
if your Make script is incorrect.

### Gradle Builds


For Gradle builds, first you need to put the following three lines
of code inside your main `build.grade` file.

```groovy
plugins {
  id "org.buildfs.gradle.buildfs-plugin" version "1.0" 
}
```

The code above applies our
[org.buildfs.gradle.buildfs-plugin](https://plugins.gradle.org/plugin/org.buildfs.gradle.buildfs-plugin) to your Gradle script
in order to enable our instrumentation.
The `buildfs` tool exploits this instrumentation
during the execution of the build,
to extract the specification of each Gradle task
(as written by the developers).

After modifying your Gradle script, analyze and test your Gradle script
by simply running the following command from the directory
where your `gradlew` file is stored.

```
buildfs gradle-build -mode online -build-task build
```

### Usage

```
❯ buildfs help
Detecting Faults in Parallel and Incremental Builds.

  buildfs SUBCOMMAND

=== subcommands ===

  gradle-build  This is the sub-command for analyzing and detecting faults in
                Gradle scripts
  make-build    This is the sub-command for analyzing and detecting faults in
                Make scripts
  version       print version information
  help          explain a given subcommand (perhaps recursively)
```

For analyzing Gradle builds

```
❯ buildfs gradle-build -help
This is the sub-command for analyzing and detecting faults in Gradle scripts

  buildfs gradle-build

=== flags ===

  -build-dir Build        directory
  -mode Analysis          mode; either online or offline
  [-build-task Build]     task to execute
  [-dump-tool-out File]   to store output from Gradle execution (for debugging
                          only)
  [-graph-file File]      to store the task graph inferred by BuildFS.
  [-graph-format Format]  for storing the task graph of the BuildFS program.
  [-print-stats]          Print stats about execution and analysis
  [-trace-file Path]      to trace file produced by the 'strace' tool.
  [-help]                 print this help text and exit
                          (alias: -?)
```

For analyzing Make builds


```
❯ buildfs make-build -help
This is the sub-command for analyzing and detecting faults in Make scripts

  buildfs make-build

=== flags ===

  -build-dir Build        directory
  -mode Analysis          mode; either online or offline
  [-build-db Path]        to Make database
  [-dump-tool-out File]   to store output from Make execution (for debugging
                          only)
  [-graph-file File]      to store the task graph inferred by BuildFS.
  [-graph-format Format]  for storing the task graph of the BuildFS program.
  [-print-stats]          Print stats about execution and analysis
  [-trace-file Path]      to trace file produced by the 'strace' tool.
  [-help]                 print this help text and exit
                          (alias: -?)
```

## Getting Started with Docker Image

After seeing how we can use `BuildFS` as a standalone tool,
it's time to see how we run and analyze real-world builds
through our Docker image.
Recall that this image contains all necessary dependencies for
running the builds and scripts for producing multiple report files.
The image contains an entrypoint script that expects the following
options:

* `-p`: A URL pointing to the *git* repository of the project
        that we want to run and analyze.
* `-v`: A commit hash, a tag, or a branch that indicates the version of the
        project that we want to analyze (default `latest`).
* `-t`: The type of the project (`gradle` or `make`).
* `-b`: This option expects a path (relative to the directory of the project)
        where the build is performed. 
* `-k`: Number of builds to perform (default 1).
* `-s`: A flag that indicates that the build is ran through `BuildFS`.
        If this is flag is not provided, we run the build without `BuildFS`.
* `-o`: A flag that beyond online analysis through `BuildFS`, it also
        performs an offline analysis on the trace stemming from the execution
        of the build. This option was used in our experiments to estimate
        the amount of time spent on the analysis of BuildFS programs.


### Example1: Make Build

To analyze an example Make build, run the following command:

```bash
docker run --rm -ti --privileged \
  -v $(pwd)/out:/home/buildfs/data buildfs \
  -p "https://github.com/dspinellis/cqmetrics.git" \
  -v "5e5495499863921ba3133a66957f98b192004507" \
  -s -t make \
  -b src
```

Some explanations:

The Docker option `--privileged` is used to enable tracing inside the
Docker container. The option `-v` is used to mount a local volume inside
the Docker container. This is used to store all the files produced
from the analysis of the build script into the given volume `$(pwd)/out`.
Specifically,
for Make builds,
`BuildFS` produces the following files inside this directory.

* `cqmetrics/build-buildfs.times`: This file contains the time for building
  the project using `BuildFS`. This file is generated if we run the container
  with the option `-s`.
* `cqmetrics/base-build.times`: This file contains the time spent for building
  the project *without* `BuildFS`. This file is  generated if the option
  `-s` is *not* provided.
* `cqmetrics/cqmetrics.times`: This file is a CSV that includes the time spent
  on the analysis of BuildFS programs and fault detection. This file is generated
  if the option `-o` (offline analysis) is provided.
* `cqmetrics/cqmetrics.faults`: This file is the report that contains the faults
  detected by `BuildFS`. This file is generated if we run the container
  with the option `-s`.
* `cqmetrics/cqmetrics.makedb`: This file is the database of the Make build
  produced by running `make -pn`. This is used for an offline analysis of a Make
  project. This file is generated if we run the container with the option `-s`.
* `cqmetrics/cqmetrics.path`: This file contains the path where we performed
  the build. This file is generated if we run the container with the option `-s`.
* `cqmetrics/cqmetrics.strace`: a system call trace corresponding
  to the build execution. This file is generated if we run the container with
  the option `-s`.

If we inspect the contains of the resulting `out/cqmetrics/cqmetrics.faults`
file, we will see something that is similar to the following:

```bash

❯ cat out/cqmetrics/cqmetrics.faults
Info: Start tracing command: fsmake-make ...
Statistics
----------
Trace entries: 19759
Tasks: 8
Files: 342
Conflicts: 4
DFS traversals: 41
Analysis time: 2.81151819229
Bug detection time: 0.0152561664581
------------------------------------------------------------
Number of Missing Inputs (MIN): 3

Detailed Bug Report:
  ==> [Task: /home/buildfs/cqmetrics/src:header.tab]

    Fault Type: MIN
      - /home/buildfs/cqmetrics/src/QualityMetrics.h: Consumed by /home/buildfs/cqmetrics/src:header.tab ( openat at line 21068 )

  ==> [Task: /home/buildfs/cqmetrics/src:header.txt]

    Fault Type: MIN
      - /home/buildfs/cqmetrics/src/QualityMetrics.h: Consumed by /home/buildfs/cqmetrics/src:header.txt ( openat at line 22386 )

  ==> [Task: /home/buildfs/cqmetrics/src:qmcalc.o]

    Fault Type: MIN
      - /home/buildfs/cqmetrics/src/BolState.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18631 )
      - /home/buildfs/cqmetrics/src/CKeyword.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18633 )
      - /home/buildfs/cqmetrics/src/CMetricsCalculator.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18563 )
      - /home/buildfs/cqmetrics/src/CharSource.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18565 )
      - /home/buildfs/cqmetrics/src/Cyclomatic.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18767 )
      - /home/buildfs/cqmetrics/src/Descriptive.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18769 )
      - /home/buildfs/cqmetrics/src/Halstead.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 19361 )
      - /home/buildfs/cqmetrics/src/NestingLevel.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 19365 )
      - /home/buildfs/cqmetrics/src/QualityMetrics.h: Consumed by /home/buildfs/cqmetrics/src:qmcalc.o ( openat at line 18711 )
```

Specifically, `BuildFS` detected three missing inputs (MIN) related to three
build tasks of the project. For example, the following fragment shows that
the task `/home/buildfs/cqmetrics/src:header.txt` has a missing input on one file
(i.e., `/home/buildfs/cqmetrics/src/QualityMetrics.h`). This means that
whenever the latter is updated, Make does not re-trigger the execution of
the task leading to stale targets.

```bash
==> [Task: /home/buildfs/cqmetrics/src:header.txt]

  Fault Type: MIN
    - /home/buildfs/cqmetrics/src/QualityMetrics.h: Consumed by /home/buildfs/cqmetrics/src:header.txt ( openat at line 22386 )
```


### Example2: Gradle Build

For running and analyzing a Gradle project using our Docker image,
run the following:


```bash
docker run --rm -ti --privileged \
  -v $(pwd)/out:/home/buildfs/data buildfs \
  -p "https://github.com/seqeralabs/nf-tower.git" \
  -v "997985c2f7e603342189effdfea122bab53a6bae" \
  -s \
  -t gradle
```

This will fetch and instrument the specified repository. For Gradle builds,
`BuildFS` will generate the same file inside the `out` except for
the `*.makedb` as it is only relevant for Make builds.

If you inspect the produced `out/nf-tower/nf-tower.faults` file you will see
the following report:

```bash
❯ cat out/nf-tower/nf-tower.faults
Info: Start tracing command: ./gradlew build --no-parallel ...
Statistics
----------
Trace entries: 897251
Tasks: 18
Files: 2877
Conflicts: 2614
DFS traversals: 10
Analysis time: 214.29347682
Bug detection time: 0.146173000336
------------------------------------------------------------
Number of Ordering Violations (OV): 3

Detailed Bug Report:
  ==> [Task: tower-backend:shadowJar] | [Task: tower-backend:distTar]

    Fault Type: OV
      - /home/buildfs/nf-tower/tower-backend/build/libs/tower-backend-19.08.0.jar: Produced by tower-backend:shadowJar ( openat at line 280041 ) and Consumed by tower-backend:distTar ( lstat at line 151875 )

  ==> [Task: tower-backend:shadowJar] | [Task: tower-backend:distZip]

    Fault Type: OV
      - /home/buildfs/nf-tower/tower-backend/build/libs/tower-backend-19.08.0.jar: Produced by tower-backend:shadowJar ( openat at line 280041 ) and Consumed by tower-backend:distZip ( lstat at line 161551 )

  ==> [Task: tower-backend:shadowJar] | [Task: tower-backend:jar]

    Fault Type: OV
      - /home/buildfs/nf-tower/tower-backend/build/libs/tower-backend-19.08.0.jar: Produced by tower-backend:shadowJar ( openat at line 280041 ) and Produced by tower-backend:jar ( openat at line 139411 )
      - /home/buildfs/nf-tower/tower-backend/build/libs/tower-backend-19.08.0.jar: Produced by tower-backend:shadowJar ( openat at line 280041 ) and Produced by tower-backend:jar ( openat at line 139411 )
```

`BuildFS` detected three ordering violations (OV).
For example, there is an ordering violations between the tasks
`tower-backend:shadowJar`,
`tower-backend:jar`.
These tasks conflict on two files
(e.g., `/home/buildfs/nf-tower/tower-backend/build/libs/tower-backend-19.08.0.jar`),
and no dependency has been specified between these tasks.

**NOTE**: In general,
Gradle builds take longer as they involve the download of JAR
dependencies and the setup of the Gradle Daemon.

## Publications

The tool is described in detail in the following paper.

* Thodoris Sotiropoulos, Stefanos Chaliasos, Dimitris Mitropoulos, and Diomidis Spinellis. 2020.
  [A Model for Detecting Faults in Build Specifications](https://doi.org/10.1145/3428212).
  In Proceedings of the ACM on Programming Languages (OOPSLA '20), 2020, Virtual, USA,
  30 pages. 
  ([doi:10.1145/3428212](https://doi.org/10.1145/3428212))

The research artifact associated with this tool can be found at https://github.com/theosotr/buildfs-eval.
