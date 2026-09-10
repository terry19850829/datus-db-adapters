#!/usr/bin/env bash
# The image calls init hooks after its configuration restart. Keep the marker
# with the data so ordinary container restarts do not require initialization.
set -euo pipefail

touch "${GREENPLUM_DATA_DIRECTORY:?}/.datus-test-initialized"
