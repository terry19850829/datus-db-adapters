#!/usr/bin/env bash
# Keep the pinned image's initialization sequence, including its synchronous
# init scripts. Only retry the temporary server start that can abort on macOS.
set -eo pipefail

export PGDATA=${PGDATA:-/var/lib/opengauss/data}
export GAUSSHOME=/usr/local/opengauss
export GAUSSLOG=${GAUSSLOG:-/gausslog}
export LD_LIBRARY_PATH="$GAUSSHOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$GAUSSHOME/bin:$PATH"

healthcheck() {
    [ -f "$PGDATA/.datus-test-provisioned" ] || return 1
    # The init server can answer local SQL before the image stops it. Require
    # the test login over TLS, which is enabled on the final server start.
    gosu omm env \
        HOME=/home/omm \
        PGSSLMODE=require \
        PGCONNECT_TIMEOUT=5 \
        gsql -h 127.0.0.1 -U "${GAUSSDB_USER:-datus}" -W "${GAUSSDB_PASSWORD:-Datus@123}" -d postgres \
        -v ON_ERROR_STOP=1 -c 'select 1' >/dev/null
}

start_temporary_server() {
    if [ "${1:-}" = gaussdb ]; then
        shift
    fi
    if gs_ctl -D "$PGDATA" -w start "$@"; then
        return 0
    fi
    echo "gaussdb: temporary server start failed, retrying once" >&2
    gs_ctl -D "$PGDATA" -w start "$@"
}

main() {
    if [ "${1:-}" = healthcheck ]; then
        healthcheck
        return
    fi

    # The image supports sourcing without executing _main. Keep its directory
    # setup and privilege drop, but re-enter this wrapper so the retry survives.
    # Its optional environment variables intentionally do not use nounset.
    # shellcheck disable=SC1091
    source /entrypoint.sh
    if [ "$(id -u)" = 0 ]; then
        mkdir -p "$GAUSSLOG"
        chown omm:omm "$GAUSSLOG"
        docker_setup_env
        docker_create_db_directories
        exec gosu omm env HOME=/home/omm bash "${BASH_SOURCE[0]}" "$@"
    fi

    # Retry in place: recovering only after _main exits would bypass the user
    # and TLS init scripts when the first temporary server start fails.
    docker_temp_server_start() { start_temporary_server "$@"; }
    _main gaussdb
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
