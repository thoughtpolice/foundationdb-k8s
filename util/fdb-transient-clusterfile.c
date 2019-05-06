/*
 * fdb-transient-clusterfile.c: inject a transient fdb.cluster file into FoundationDB
 * Copyright (C) 2019 Austin Seipp <aseipp@pobox.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * this program is a quick hack that uses memfd_create in order to create a
 * temporary, process-local, invisible fdb.cluster file that is 'injected' into
 * foundationdb processes. it essentially acts like a wrapper around the
 * cluster executables that injects a hidden file at runtime.
 *
 * to use this, you must set the FDB_CLUSTER_STRING environment variable to the
 * cluster string containing foundationdb coordination servers. next, the first
 * argument must be a path to some foundationdb executable. any following
 * arguments are passed directly to the executable that is invoked.
 *
 * before calling exec(), this program sets the FDB_CLUSTER_FILE environment
 * variable to the path under /proc containing the anonymous, process-local
 * file, which will be passed onto the child.
 *
 * the intention of this program is to have fully 'stateless' cluster files
 * that are injected by some other orchestrator program. while foundationdb
 * will rewrite the file contents if coordinators are removed, this is a more
 * rare occurrence that is normally handled manually, and furthermore,
 * coordinator IPs are typically stable.
 *
 * see here for the original idea. we use memfd_create instead of
 * open(O_TMPFILE) since it seems to actually work better that way when passing
 * to a child process, vs doing it in the process that calls fdb_open itself
 * (the memfd approach below would work in both cases):
 *
 *     https://forums.foundationdb.org/t/allowing-client-apis-to-use-an-in-memory-fdb-cluster-file/675
 *
 * for example, try something like:
 *
 *     $ export FDB_CLUSTER_STRING="xxxxxxxx:xxxxxxxx@172.16.222.53:14500"
 *     $ ./fdb-transient-clusterfile $(which env) | grep FDB_CLUSTER_FILE
 *     FDB_CLUSTER_FILE=/proc/self/fd/3
 *     $ ./fdb-transient-clusterfile $(which cat) /proc/self/fd/3 && echo
 *     xxxxxxxx:xxxxxxxx@172.16.222.53:14500
 *     $
 */

// memfd_create(2)
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <limits.h>

#include <unistd.h>
#include <err.h>

#include <sys/mman.h>
#include <fcntl.h>

//#define DEBUG

void
usage(char* p, int r)
{
        // TODO(aseipp): fixme
        fprintf(stderr, "usage: %s <COMMAND> ARGS...\n", p);
        exit(r);
}

int
main(int ac, char** av)
{
        // sanity
        if (ac < 2)
                usage(av[0], EXIT_FAILURE);

        char* program = av[1];
        if (access(program, R_OK | X_OK) == -1)
                err(EXIT_FAILURE, "access(%s)", program);

        char* cstring = getenv("FDB_CLUSTER_STRING");
        if (cstring == NULL)
                usage(av[0], EXIT_FAILURE);

        // open temp file. respect XDG_TEMP_DIR or just /tmp
        char* tmpdir = getenv("XDG_RUNTIME_DIR");
        tmpdir = (tmpdir == NULL) ? "/tmp" : tmpdir;
        int tempfd = memfd_create("fdb.cluster", 0);
        if (tempfd == -1)
                err(EXIT_FAILURE, "open(O_TMPFILE)");

        if (strlen(cstring) != (size_t)write(tempfd, cstring, strlen(cstring))) {
                // TODO(aseipp): make this robust, eintr loop, etc
                errx(EXIT_FAILURE, "could not write FDB_CLUSTER_STRING!"); 
        }

        // this memfd path will be resolvable in the child process
        char fdpath[PATH_MAX+1] = { 0, };
        snprintf(fdpath, sizeof(fdpath)-1, "/proc/self/fd/%" PRId32, tempfd);

#ifdef DEBUG
        printf("got path: %s\n", fdpath);
#endif

        // set it. easier than crafting a custom envp with execve, etc.
        if (setenv("FDB_CLUSTER_FILE", fdpath, 1) == -1)
                err(EXIT_FAILURE, "setenv(FDB_CLUSTER_FILE)");

        // go go gadget
        return execv(program, ++av);
}
