# FoundationDB + K8S simulation tests

This repository is (currently) intended to be a set of tools and a harness for
running very large amounts of [FoundationDB](https://www.foundationdb.org)
Simulation Tests on top of a large [Kubernetes](https://kubernetes.io) cluster.
The idea is that you can use this to test FoundationDB builds you create, or
patches you create to the core, or various build/packaging choices (different
compiler versions, optimizations), etc. This includes some preliminary
functionality to package FoundationDB binaries into usable Docker images.

Currently, this is only intended to test my builds of FoundationDB for
[Nixpkgs](https://nixos.org), and is heavily designed around that. In the
future it should be possible to make it easier for third parties to use this
infrastructure to create e.g.  their own FoundationDB docker images from some
on-disk source repo (automated by Nix) or it may become a more general
framework for FoundationDB-on-K8S.

## Background

FoundationDB is designed and tested using a powerful 'simulation mode'. In this
mode, an entire simulated database cluster exists within a single process, that
is executed in a completely deterministic fashion, and seeded by a randomly
chosen seed. The intention is that you run a simulation of a cluster many
times, using a large number of seeds, in order to rattle out bugs. Because the
simulation is deterministic, if a bug is found, you can reproduce it by simply
re-using the same seed value.

In a sense, FoundationDB is tested using a similar assumption that
property-based testing frameworks like the Haskell QuickCheck library operate
on -- but in the domain of distributed, asynchronous systems.

FoundationDB simulation tests are written using a simple configuration file
that describes the simulation to be run. NixOS packages for FoundationDB
include these tests within the binary packages we ship. This repository
contains some infrastructure to take these binary packages, put them inside
Docker images, and run these tests a large number of times inside the container
-- in turn, you can deploy these docker images as Kubernetes [Job
objects](https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/).

Currently, only pre-release versions of FoundationDB 6.1 are supported with
these images. These packages are built using [a fork of
nixpkgs](https://github.com/NixOS/nixpkgs/pull/61009) containing FoundationDB
6.1 builds using CMake. Soon(-ish), this pull request will be merged upstream,
and these Docker images will track FoundationDB stable releases.

## Usage

You need Nix 2.0 at least (preferably, 2.2 or later). Get it from
<https://nixos.org/nix/>, or just run (as a user who can `sudo`):

```bash
$ sh <(curl https://nixos.org/nix/install) --daemon
```

### Build, Load Docker Image

Build the docker image:

```
$ nix build -f default.nix docker.foundationdb61
```

This puts a symlink named `./result` in the CWD that points to a docker archive
`.tar.gz` file. You can load this into your Docker daemon now -- the image
`foundationdb:TAG` will be available, where the tag is a version number that
fully identifies the FoundationDB version (including `git` hash for any
pre-release or unstable builds):

```
$ docker load < result

$ docker images foundationdb
REPOSITORY          TAG                    IMAGE ID            CREATED             SIZE
foundationdb        6.1.5pre4879_91547e7   2e73a59d2644        49 years ago        116MB
```

### Test Docker Image

Test the docker image by running a simulation test. We can run the
`fast-atomicops` test 10 times as an example:

```
$ docker run --rm foundationdb:6.1.5pre4879_91547e7 simulate fast/AtomicOps 10
NOTE: simulation test fast/AtomicOps (10 rounds)...
NOTE: running simulation #1 (seed = 0x136276c4)... ok
NOTE: running simulation #2 (seed = 0x2b807568)... ok
NOTE: running simulation #3 (seed = 0x8b3e79e3)... ok
NOTE: running simulation #4 (seed = 0x11581fb5)... ok
NOTE: running simulation #5 (seed = 0x88159bf0)... ok
NOTE: running simulation #6 (seed = 0xa27d94fb)... ok
NOTE: running simulation #7 (seed = 0x5081e040)... ok
NOTE: running simulation #8 (seed = 0x9ad8c268)... ok
NOTE: running simulation #9 (seed = 0x741db05f)... ok
NOTE: running simulation #10 (seed = 0x462fd316)... ok
NOTE: finished fast/AtomicOps; 10 total sim rounds, 10/10 successful sim runs
```

Seed values are output for every run, and in case of failure, `stdout` and
trace logs are barfed out to the terminal. The default number of rounds is 100.

See `util/entrypoint.sh` for the entry point script that's used here.

### Start K8S Cluster (Kind)

You need a K8S cluster. I have a powerful Ryzen ThreadRipper machine with many
cores and a lot of RAM, so rather than paying for one, I use
[kind](https://github.com/kubernetes-sigs/kind) for this. While `kind` is still
a beta project, Jobs are a core kubernetes type that seem to work alright.

You need at least Kind 0.2.1 in order to load arbitrary docker tarballs or
docker images from the host into the Kind cluster. If you're using some other
hosting/K8S Cloud service, you'll need to push the docker image from above into
an available registry (not covered here, and not currently supported directly.)

```bash
$ kind create cluster

$ export KUBECONFIG="$(kind get kubeconfig-path --name="kind")"

$ kubectl cluster-info
Kubernetes master is running at https://localhost:45803
KubeDNS is running at https://localhost:45803/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

$ kind load docker-image foundationdb:6.1.5pre4879_91547e7
```

The image is now loaded into the cluster, which can be run inside a given Pod.

### Build K8S Simulation Manifests

Now you need to build YAML manifests for the simulation jobs. These are
automatically generated by Nix as well:

```bash
$ nix build -f default.nix k8s.simulation-tests.foundationdb61
```

This will result in a symlink named `./result` that points _to a directory_
containing many `.yaml` files, each with a job for a simulation test, included
with FoundationDB. For example:

```bash
$ cat result/simulation-fast-atomicops.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: simulation-fast-atomicops
  labels:
    group: simulation
    test: fast-atomicops
spec:
  parallelism: 2
  completions: 4
  template:
    metadata:
      name: sim-fast-atomicops
      labels:
        group: simulation
        test: fast-atomicops
    spec:
      containers:
      - name: sim-fast-atomicops
        image: foundationdb:6.1.5pre4879_91547e7
        args: [ "simulate", "fast/AtomicOps", "25" ]
        resources:
          limits:
            memory: 768M
          requests:
            memory: 128M
      restartPolicy: Never
```

This batch Job will run the same test we ran before natively with `docker` --
but each Pod will instead run 25 rounds, a total of 4 times, with 2 concurrent
pods active at any given time (for a total of 100 simulated tests).

### Run simulation manifest

```bash
$ kubectl apply -f result/simulation-fast-atomicops.yaml
job.batch/simulation-fast-atomicops created

$ kubectl get jobs.batch simulation-fast-atomicops
NAME                        COMPLETIONS   DURATION   AGE
simulation-fast-atomicops   0/4           6s         6s

$ kubectl get pods -l group=simulation -l test=fast-atomicops
NAME                              READY   STATUS    RESTARTS   AGE
simulation-fast-atomicops-cvvbx   1/1     Running   0          36s
simulation-fast-atomicops-rmzmk   1/1     Running   0          36s
```

You can delete the job at any time with:

```bash
$ kubectl delete jobs.batch simulation-fast-atomicops
```

### Run the marathon

If you're feeling daring and you have a big K8S cluster available, you can run
_every_ simulation test job all at once by applying the
`result/full-simulation.yaml` manifest as above. It's one big concatenation of
every other manifest.

Note that (I'd think) the default pod specifications are somewhat grossly
over-conservative for many of the jobs, so you should probably have a fairly
beefly cluster available with lots of RAM and cores if you expect this to
complete in any reasonable amount of time.

Ideally, over time, the job specifications can have their resource limits
tweaked to more accurately reflect reality and make the pod scheduler's job
easier.

### Hacking notes

The source code isn't very magical but *is* very Nix specific. Tests are
automatically scanned from NixOS binary packages of FoundationDB, overrides are
possible for individual pod/job specs in `default.nix`, etc. If you have
questions, feel free to ask.

# License

Apache 2.0. See `LICENSE.txt` for details.
