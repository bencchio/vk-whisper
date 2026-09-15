#!/bin/bash
#
# Streaming latency test harness for vk-whisper-stream.
#
# Launches vk-whisper-stream with the given --step/--length, timestamps
# every line of output (so latency between speaking and seeing text can be
# measured after the fact), and signals when to start speaking. Requires a
# live speaker — this does not replay a fixed audio file, since the whole
# point is to measure the real streaming pipeline against a live mic.
#
# Usage:
#   vk/bench/stream-latency.sh [label] [step_ms] [length_ms] [duration_s] [build-dir] [model]
#
# Defaults:
#   label      = step<step_ms>-len<length_ms>
#   step_ms    = 3000
#   length_ms  = 10000
#   duration_s = 25
#   build-dir  = ~/Build/vk-whisper
#   model      = models/ggml-large-v3-turbo-q8_0.bin
#
# Output: vk/bench/results/stream-<label>.log (timestamped lines, HH:MM:SS.mmm)
#
# After it exits, inspect the log for how many seconds elapsed between
# "[Start speaking]" (harness launch) and the first line containing real
# transcribed text vs. hallucinated filler ("Gracias.", etc.).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

STEP_MS="${2:-3000}"
LENGTH_MS="${3:-10000}"
DURATION_S="${4:-25}"
BUILD_DIR="${5:-$HOME/Build/vk-whisper}"
MODEL="${6:-models/ggml-large-v3-turbo-q8_0.bin}"
LABEL="${1:-step${STEP_MS}-len${LENGTH_MS}}"

CLI="${BUILD_DIR}/bin/vk-whisper-stream"

if [ ! -x "${CLI}" ]; then
    echo "Error: vk-whisper-stream not found at ${CLI}" >&2
    echo "Build it with WHISPER_SDL2=ON, e.g.:" >&2
    echo "  cmake -B ${BUILD_DIR} -S . -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_SDL2=ON" >&2
    echo "  cmake --build ${BUILD_DIR} -j\$(nproc)" >&2
    exit 1
fi

if [ ! -f "${MODEL}" ]; then
    echo "Error: model not found at ${MODEL}" >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/results"
LOG="${SCRIPT_DIR}/results/stream-${LABEL}.log"

echo "Launching vk-whisper-stream (step=${STEP_MS}ms length=${LENGTH_MS}ms, ${DURATION_S}s window)..."
timeout "${DURATION_S}" "${CLI}" -m "${MODEL}" -l es --step "${STEP_MS}" --length "${LENGTH_MS}" -t 4 2>&1 \
    | awk '{ "date +%H:%M:%S.%3N" | getline ts; close("date +%H:%M:%S.%3N"); print ts, $0; fflush() }' \
    > "${LOG}" &
PID=$!

# Give the process a moment to init the model/mic before cueing the speaker.
sleep 3
echo
echo ">>> EMPEZÁ A HABLAR AHORA <<<"
echo

wait "${PID}" 2>/dev/null || true

echo "Done. Log: ${LOG}"
echo "To inspect: grep -a '^[0-9][0-9]:' '${LOG}'"
