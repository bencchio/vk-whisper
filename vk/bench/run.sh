#!/bin/bash
#
# Benchmark runner for vk-whisper (Vulkan backend).
#
# Runs whisper-cli with fixed parameters against a fixed sample so results
# are comparable across commits/builds. Appends a row to results/history.csv
# and writes the full raw output to results/<label>.log.
#
# Usage:
#   vk/bench/run.sh [label] [build-dir] [model] [sample] [threads]
#   EXTRA_ARGS="-bs 1 -bo 1" vk/bench/run.sh [label] ...   # pass extra whisper-cli flags
#   TASKSET_CPUS="0-3" vk/bench/run.sh [label] ...         # pin to CPU cores via taskset
#
# Defaults:
#   label     = git short hash + dirty flag
#   build-dir = ~/Build/vk-whisper
#   model     = models/ggml-base.en.bin
#   sample    = samples/jfk.wav
#   threads   = 4
#   EXTRA_ARGS = (none)
#   TASKSET_CPUS = (none, no pinning)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

BUILD_DIR="${2:-$HOME/Build/vk-whisper}"
MODEL="${3:-models/ggml-base.en.bin}"
SAMPLE="${4:-samples/jfk.wav}"
THREADS="${5:-4}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
TASKSET_CPUS="${TASKSET_CPUS:-}"

RUN_PREFIX=()
if [ -n "${TASKSET_CPUS}" ]; then
    if ! command -v taskset >/dev/null 2>&1; then
        echo "Error: taskset not found (needed for TASKSET_CPUS)" >&2
        exit 1
    fi
    RUN_PREFIX=(taskset -c "${TASKSET_CPUS}")
fi

GIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DIRTY=""
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    DIRTY="-dirty"
fi
LABEL="${1:-${GIT_HASH}${DIRTY}}"

CLI="${BUILD_DIR}/bin/whisper-cli"

if [ ! -x "${CLI}" ]; then
    echo "Error: whisper-cli not found at ${CLI}" >&2
    echo "Build it first, e.g.:" >&2
    echo "  cmake -B ${BUILD_DIR} -S . -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_TESTS=OFF" >&2
    echo "  cmake --build ${BUILD_DIR} -j\$(nproc)" >&2
    exit 1
fi

if [ ! -f "${MODEL}" ]; then
    echo "Error: model not found at ${MODEL}" >&2
    echo "Download it, e.g.: models/download-ggml-model.sh base.en" >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/results"
RAW_LOG="${SCRIPT_DIR}/results/${LABEL}.log"
HISTORY="${SCRIPT_DIR}/results/history.csv"

echo "Running benchmark: label=${LABEL} model=${MODEL} sample=${SAMPLE} threads=${THREADS} extra_args=${EXTRA_ARGS} taskset_cpus=${TASKSET_CPUS:-none}"
# shellcheck disable=SC2086
"${RUN_PREFIX[@]}" "${CLI}" -m "${MODEL}" -f "${SAMPLE}" -t "${THREADS}" ${EXTRA_ARGS} > "${RAW_LOG}" 2>&1 || {
    echo "whisper-cli failed, see ${RAW_LOG}" >&2
    exit 1
}

extract_ms() {
    # $1 = label to grep for in the timings block
    grep "$1" "${RAW_LOG}" | grep -oE '[0-9]+\.[0-9]+ ms' | head -1 | grep -oE '[0-9]+\.[0-9]+'
}

LOAD=$(extract_ms "load time")
MEL=$(extract_ms "mel time")
ENCODE=$(extract_ms "encode time")
DECODE=$(extract_ms "decode time")
BATCHD=$(extract_ms "batchd time")
SAMPLE_T=$(extract_ms "sample time")
TOTAL=$(extract_ms "total time")
GPU=$(grep -m1 "Vulkan devices" -A1 "${RAW_LOG}" | tail -1 | sed -E 's/^ggml_vulkan: 0 = //' | cut -d'|' -f1 | sed 's/[[:space:]]*$//')

if [ ! -f "${HISTORY}" ]; then
    echo "timestamp,label,gpu,model,sample,threads,load_ms,mel_ms,encode_ms,decode_ms,batchd_ms,sample_ms,total_ms,taskset_cpus" > "${HISTORY}"
fi

echo "$(date -Iseconds),${LABEL},\"${GPU}\",$(basename "${MODEL}"),$(basename "${SAMPLE}"),${THREADS},${LOAD},${MEL},${ENCODE},${DECODE},${BATCHD},${SAMPLE_T},${TOTAL},${TASKSET_CPUS}" >> "${HISTORY}"

echo
echo "Result (${LABEL}): total=${TOTAL}ms encode=${ENCODE}ms decode=${DECODE}ms batchd=${BATCHD}ms"
echo "Raw log: ${RAW_LOG}"
echo "History: ${HISTORY}"
