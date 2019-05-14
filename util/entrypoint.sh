#!/usr/bin/env bash

set -eo pipefail
[[ -n "${DEBUG}" ]] && set -x

VALID_CMDS=(server backup restore dr cli backup_agent dr_agent simulate)
CMD="$1";
shift;
if [[ ! " ${VALID_CMDS[@]} " =~ " ${CMD} " ]]; then
        >&2 echo "ERROR: invalid command '${CMD}'"
        exit 1
fi

# fast path: if we're running simulation, we don't even need a cluster
# string or anything else, just the test name.
if [[ "${CMD}" == "simulate" ]]; then
        TEST="$1"
        ROUNDS="${2:-100}"
        [[ -z "${TEST}" ]] && >&2 echo "ERROR: simulation run most provide test name!" && exit 1
        [[ ! -f "/share/test/${TEST}.txt" ]] && >&2 echo "ERROR: simulation test file '/share/test/${TEST}.txt' does not exist!" && exit 1

        echo "NOTE: simulation test ${TEST} (${ROUNDS} rounds)..."

        successes=0
        failures=0
        buggy=0
        for x in $(seq 1 ${ROUNDS}); do
          SEED=$(od -vAn -N4 -tx4 < /dev/urandom | awk '{print "0x"$1}')
          BUGGIFY=$(($RANDOM%2))

          if [ "$BUGGIFY" -eq 0 ]; then
            BUGGIFY="off"
          else
            BUGGIFY="on"
            buggy=$((buggy+1))
          fi

          echo -n "NOTE: running simulation #$x (buggify = $BUGGIFY, seed = $SEED)... "
          fdbserver -r simulation -f "/share/test/${TEST}.txt" -s "$SEED" -b "$BUGGIFY" > /data/sim-log.txt
          ret="$?"
          if [ "$ret" -eq 0 ]; then
            successes=$((successes+1))
            echo ok
          else
            failures=$((failures+1))
            echo "ERROR: rc = $ret, logs as follows:"
            cat /data/sim-log.txt

            echo; echo "ERROR: trace follows:"; echo
            cat /data/trace*.xml
            echo; echo
          fi

          rm -f /data/trace*.xml
        done

        success_ratio="$(echo "scale=2; ($successes*100)/$ROUNDS" | bc)%"
        buggy_ratio="$(echo "scale=2; ($buggy*100)/$ROUNDS" | bc)%"
        echo "NOTE: finished ${TEST}; $ROUNDS total sim rounds, $buggy ($buggy_ratio) which were buggy; $successes/$ROUNDS ($success_ratio) successful sim runs";
        exit 0
fi

# every other mode needs the name, and the cluster string
[[ -z "${FDB_CLUSTER_STRING}" ]] && \
        >&2 echo "ERROR: FDB_CLUSTER_STRING must be set!" && \
        exit 1

[[ -z "$1" ]] && \
        >&2 echo "ERROR: command must be present: server, backup, restore, dr, cli, backup_agent, dr_agent" && \
        exit 1


[[ "${CMD}" == "dr_agent" ]] && >&2 echo "ERROR: NIH" && exit 1
[[ "${CMD}" == "backup_agent" ]] && exec /bin/fdb-transient-clusterfile /libexec/backup_agent "$@"
[[ "${CMD}" == "cli" ]] && exec /bin/fdb-transient-clusterfile /bin/fdbcli "$@"
[[ "${CMD}" == "dr" ]] && exec /bin/fdb-transient-clusterfile /bin/fdbdr "$@"
[[ "${CMD}" == "backup" ]] && exec /bin/fdb-transient-clusterfile /bin/fdbbackup "$@"
[[ "${CMD}" == "restore" ]] && exec /bin/fdb-transient-clusterfile /bin/fdbrestore "$@"

# the only thing left is a server run
[[ "${CMD}" != "server" ]] && >&2 echo "ERROR: invalid command '${CMD}'!" && exit 1

[[ -z "${MACHINE_ID}" ]] && \
        >&2 echo "ERROR: MACHINE_ID must be set!" && \
        exit 1
[[ -z "${DATACENTER_ID}" ]] && \
        >&2 echo "ERROR: DATACENTER_ID must be set!" && \
        exit 1

if [[ -z "${PROCESS_CLASS}" ]]; then
        CLASS_ARGS=()
else
        VALID_CLASSES=(storage transaction resolution proxy master test unset stateless log router cluster_controller)
        if [[ ! " ${VALID_CLASSES[@]} " =~ " ${PROCESS_CLASS} " ]]; then
                >&2 echo "ERROR: invalid process class '${PROCESS_CLASS}'"
                exit 1
        fi

        CLASS_ARGS=(-c "${PROCESS_CLASS}")
fi

PORT=${PORT:-4500}
DATADIR=/data/store
LOGDIR=/data/logs

mkdir -p "$DATADIR" "$LOGDIR"
exec /bin/fdb-transient-clusterfile \
        /bin/fdbserver \
        -p "auto:${PORT}" \
        -d "$DATADIR" \
        -L "$LOGDIR" \
        -i "$MACHINE_ID" \
        -a "$DATACENTER_ID" \
        "${CLASS_ARGS[@]}" \
        "$@"
