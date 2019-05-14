{ nixpkgs ? null
}:

with builtins;

let
  config = {
    packageOverrides = pkgs: with pkgs; {};
  };

  pkgs = import (if nixpkgs != null then nixpkgs else fetchTarball {
    url    = "https://github.com/thoughtpolice/nixpkgs/archive/aab8f71ad10012a3b535b0699117c9adfab92b94.tar.gz";
    sha256 = "0dw6swfbh1qw36jg22cwgcimlh8njwbjfaxi27c04cw4bjwjj052";
  }) { inherit config; };

  jobs = rec {
    transient-clusterfile = pkgs.callPackage ({ stdenv }:
      stdenv.mkDerivation rec {
        name = "fdb-transient-clusterfile-${version}";
        version = "0.1";
        src = ./util/fdb-transient-clusterfile.c;

        unpackPhase = ":";
        configurePhase = ":";
        buildPhase = "gcc -O2 -Wall -Wextra ${src}";
        installPhase = ''install -D -m555 a.out $out/bin/fdb-transient-clusterfile'';
      }) {};

    entrypoint = pkgs.writers.writeBashBin "entrypoint" (readFile ./util/entrypoint.sh);

    docker =
      let makeDockerImage = fdb: pkgs.dockerTools.buildLayeredImage {
        name = "foundationdb";
        tag = fdb.version;

        contents = with pkgs;
          [ bash bc gawk coreutils
            entrypoint fdb transient-clusterfile
          ];

        config = {
          Entrypoint = [ "/bin/entrypoint" ];
          WorkingDir = "/data";
          Volumes = { "/data" = {}; };
        };
      };
    in {
      foundationdb61 = makeDockerImage pkgs.foundationdb61;
    };

    k8s =
      let
        jobSettingsOverrides =

          # ---------------------------------------------------------------------
          # Default K8S Job object limits. These defaults specify the
          # memory/parallelism necessary for every job, whether they can run
          # concurrently, IFF they have not been overridden below. Generally,
          # these are overly conservative estimates; individual tests should be
          # sampled and see if they can get away with different (more
          # stringent) requirements, which should help the pod scheduler.

          let defaults = {

                # Maximum memory the Job can allocate.
                MEMORYLIMIT   = "2G";

                # Default initial memory request that the pod scheduler will try
                # to satisfy, when creating pods for the job.
                MEMORYREQUEST = "512M";

                # The number of testing rounds to execute when a Job is run. e.g.
                # the default 100 means every simulation test will be run 100 times once
                # a job pod is started.
                ROUNDS        = 100;

                # How many of these jobs can be run in parallel. By default, so the cluster
                # doesn't get saturated, start with 1.
                PARALLELISM   = 1;

                # How many times this job needs to be completed for the whole job to be
                # considered successful. Each completion executes ROUND number of simulations
                # of a specific test.
                COMPLETIONS   = 1;
              };
            
          # EXAMPLE: If you have ROUNDS=5000, PARALLELISM=10, COMPLETIONS=100,
          # all for a given simulation test job 'F', then you will end up
          # running 100 pods for test 'F', with a maximum of 10 pods running
          # concurrently at any time, each pod executing the simulation 5000
          # times, for a total of 5000*100 = 500000 individual runs of a single
          # test.

          in pkgs.lib.mapAttrs (_: v: defaults // v) {
               inherit defaults;

               # -----------------------------------------------------------------
               # K8S overrides for specific jobs. These pairs specify any
               # overrides necessary for a specific job, which are intended to
               # help guide the scheduler when managing the pods. The left hand
               # side is the "normalized" name of a test file (e.g.
               # 'fast/AtomicOps.txt' becomes 'fast-atomicops') which will be
               # looked up, while the right hand side is any overrides of the
               # above default settings. If the RHS does not contain some value
               # from the above settings (e.g. 'ROUNDS' is left out), it will
               # use the default value (resp. 100)

               fast-atomicops = { MEMORYREQUEST = "128M"; MEMORYLIMIT = "768M"; ROUNDS = 25; COMPLETIONS = 4; PARALLELISM = 2; };

             };

        # This builds Kubernetes job manifests from a template, used to run
        # every simulation test a ton of times with some parallelism involved.
        settingsJSON = pkgs.writeText "settins.json" (builtins.toJSON jobSettingsOverrides);
        simulation-manifests = fdb: pkgs.runCommandNoCC "simulation-manifests" { buildInputs = [ pkgs.jq ]; } ''
          mkdir $out

          for x in $(cd ${fdb.out}/share/test && find . -type f -printf '%P\n'); do
            FILENAME=''${x%.txt}
            SHORTNAME=$(echo $FILENAME | sed 's#/#-#g' | tr '[:upper:]' '[:lower:]')
            VERSIONTAG="${fdb.version}"

            echo "creating manifest for simulation test ($SHORTNAME.yaml)"
            jq -r '."'$SHORTNAME'" // .defaults | to_entries | map("\(.key)=\(.value|tostring)")|.[]' < ${settingsJSON} > vars
            source ./vars
            substitute ${./k8s/batch-test.yaml.in} $out/simulation-$SHORTNAME.yaml \
              --subst-var SHORTNAME \
              --subst-var FILENAME \
              --subst-var VERSIONTAG \
              --subst-var MEMORYLIMIT \
              --subst-var MEMORYREQUEST \
              --subst-var ROUNDS \
              --subst-var PARALLELISM \
              --subst-var COMPLETIONS
          done

          echo "creating meta simulation test (full-simulation.yaml)"
          for x in $(find $out -type f -iname '*.yaml'); do
            cat "$x"  >> "$out/full-simulation.yaml"
            echo "---" >> "$out/full-simulation.yaml"
          done
          echo done
        '';
    in {
      simulation-tests = {
        inherit settingsJSON;
        foundationdb61 = simulation-manifests pkgs.foundationdb61;
      };
    };
  };

in jobs
