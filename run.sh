#!/usr/bin/env bash

MODE="${1:-}"
EXTRA_AGENT_ENV_ARGS=()
TEMP_TASK_ROOTS=()

cleanup_temp_tasks() {
  local dir
  for dir in "${TEMP_TASK_ROOTS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup_temp_tasks EXIT

EXCLUDE=(
  gh-repo-analytics
  mhc-layer-impl
  pedestrian-traffic-counting
  pg-essay-to-audiobook
  scheduling-email-assistant
  speaker-diarization-subtitles
  trend-anomaly-causal-inference
  video-filler-word-remover
  video-tutorial-indexer
  diff-transformer_impl
  exoplanet-detection-period
)

load_api_keys() {
  if [[ -f "$HOME/.bashrc" ]]; then
    eval "$(sed -n -E '/^[[:space:]]*export[[:space:]]+(OPENAI_API_KEY|AZURE_OPENAI_API_KEY)=/p' "$HOME/.bashrc")"
  fi

  : "${OPENAI_API_KEY:?OPENAI_API_KEY must be set in ~/.bashrc or the environment}"
}

use_vllm() {
  unset AZURE_API_KEY AZURE_API_BASE AZURE_API_VERSION AZURE_OPENAI_API_KEY AZURE_OPENAI_ENDPOINT
  unset OPENAI_API_TYPE

  export OPENAI_API_BASE="http://10.225.68.24:1700/v1"
  export OPENAI_BASE_URL="http://10.225.68.24:1700/v1"
}

is_excluded() {
  local task="$1"
  [[ " ${EXCLUDE[*]} " == *" ${task} "* ]]
}

each_task() {
  find tasks -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | shuf
}

prepare_task_copy() {
  local task="$1"
  local tmp_root task_copy dockerfile

  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/skillsbench-task-${task}.XXXXXX")
  TEMP_TASK_ROOTS+=("$tmp_root")
  task_copy="${tmp_root}/${task}"
  cp -a "tasks/${task}" "$task_copy"

  dockerfile="${task_copy}/environment/Dockerfile"
  if [[ -f "$dockerfile" ]] && ! grep -q "mkdir -p /app" "$dockerfile"; then
    {
      printf '\n'
      printf '# Local run workaround: BenchFlow uploads task skills to /app/skills.\n'
      printf 'RUN mkdir -p /app\n'
    } >> "$dockerfile"
  fi

  printf '%s\n' "$task_copy"
}

run_bench_pair() {
  local agent="$1"
  local model="$2"
  local job_prefix="$3"
  local task timestamp task_dir

  for task in $(each_task); do
    if is_excluded "$task"; then
      echo "****Skipping excluded task: $task****"
      continue
    fi

    echo "=============================================================="
    echo "checking task:${task}"
    uv run bench tasks check "tasks/${task}"
    echo "-------------------------------"

    task_dir=$(prepare_task_copy "$task")
    timestamp=$(date +"%Y-%m-%d__%H-%M-%S")
    echo "task:${task} with skills"
    uv run bench eval create \
      --tasks-dir "$task_dir" \
      --agent "$agent" \
      --model "$model" \
      "${EXTRA_AGENT_ENV_ARGS[@]}" \
      --jobs-dir "jobs/${job_prefix}__withskills__${task}___${timestamp}" \
      --skills-dir "${task_dir}/environment/skills/"

    echo "-------------------------------"
    echo "task:${task} without skills"
    uv run bench eval create \
      --tasks-dir "$task_dir" \
      --agent "$agent" \
      --model "$model" \
      "${EXTRA_AGENT_ENV_ARGS[@]}" \
      --jobs-dir "jobs/${job_prefix}__withoutskills__${task}___${timestamp}"

    echo "=============================================================="
  done
}

run_codex() {
  EXTRA_AGENT_ENV_ARGS=()
  load_api_keys
  : "${AZURE_OPENAI_API_KEY:?AZURE_OPENAI_API_KEY must be set in ~/.bashrc or the environment}"

  export OPENAI_BASE_URL="https://sub-lgeci-tai-opneai.openai.azure.com/openai/v1/"
  export OPENAI_API_BASE="https://sub-lgeci-tai-opneai.openai.azure.com/openai/v1/"
  export BENCHFLOW_PROVIDER_NAME=azure
  export BENCHFLOW_PROVIDER_BASE_URL="$OPENAI_BASE_URL"
  export BENCHFLOW_PROVIDER_API_KEY="$OPENAI_API_KEY"
  export CODEX_WIRE_API=responses

  run_bench_pair "codex-acp" "gpt-5.3-codex" "gpt-5.3-codex"
}

run_openclaw() {
  load_api_keys
  use_vllm

  export BENCHFLOW_PROVIDER_NAME="vllm"
  export BENCHFLOW_PROVIDER_BASE_URL="$OPENAI_BASE_URL"
  export BENCHFLOW_PROVIDER_API_KEY="yyy"
  export BENCHFLOW_PROVIDER_PROTOCOL="openai-completions"
  EXTRA_AGENT_ENV_ARGS=(
    --agent-env "BENCHFLOW_PROVIDER_BASE_URL=${BENCHFLOW_PROVIDER_BASE_URL}"
    --agent-env "BENCHFLOW_PROVIDER_API_KEY=${BENCHFLOW_PROVIDER_API_KEY}"
    --agent-env "BENCHFLOW_PROVIDER_PROTOCOL=${BENCHFLOW_PROVIDER_PROTOCOL}"
  )

  local model="Qwen3.6-35B-A3B"
  local vllm_model_id="Qwen/${model}"
  local bench_model="vllm/${vllm_model_id}"
  local models_json

  models_json=$(curl -fsS -H "Authorization: Bearer ${BENCHFLOW_PROVIDER_API_KEY}" "${OPENAI_BASE_URL}/models" 2>/dev/null || true)
  if [[ "$models_json" != *"\"${vllm_model_id}\""* ]]; then
    echo "Warning: ${OPENAI_BASE_URL}/models did not list '${vllm_model_id}'."
    echo "OpenClaw will run with '${bench_model}', which should route to vLLM model '${vllm_model_id}'."
  fi

  run_bench_pair "openclaw" "$bench_model" "openclaw__${model}"
}

case "$MODE" in
  codex)
    run_codex
    ;;
  openclaw)
    run_openclaw
    ;;
  *)
    echo "Usage: bash run.sh codex|openclaw"
    exit 2
    ;;
esac
