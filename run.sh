#!/usr/bin/env bash

MODE="${1:-}"

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

activate_skillsbench() {
  source "$(conda info --base)/etc/profile.d/conda.sh"
  conda activate skillsbench
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

run_bench_pair() {
  local agent="$1"
  local model="$2"
  local job_prefix="$3"
  local task timestamp

  for task in $(each_task); do
    if is_excluded "$task"; then
      echo "****Skipping excluded task: $task****"
      continue
    fi

    echo "=============================================================="
    echo "checking task:${task}"
    bench tasks check "tasks/${task}"
    echo "-------------------------------"

    timestamp=$(date +"%Y-%m-%d__%H-%M-%S")
    echo "task:${task} with skills"
    bench eval create \
      -t "tasks/${task}" \
      -a "$agent" \
      -m "$model" \
      -o "jobs/${job_prefix}__withskills__${task}___${timestamp}" \
      -s "tasks/${task}/environment/skills/"

    echo "-------------------------------"
    echo "task:${task} without skills"
    bench eval create \
      -t "tasks/${task}" \
      -a "$agent" \
      -m "$model" \
      -o "jobs/${job_prefix}__withoutskills__${task}___${timestamp}"

    echo "=============================================================="
  done
}

run_codex() {
  activate_skillsbench
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
  activate_skillsbench
  load_api_keys
  use_vllm

  export BENCHFLOW_PROVIDER_NAME="vllm"
  export BENCHFLOW_PROVIDER_BASE_URL="$OPENAI_BASE_URL"
  export BENCHFLOW_PROVIDER_API_KEY="$OPENAI_API_KEY"
  export BENCHFLOW_PROVIDER_PROTOCOL="openai-completions"

  local model="Qwen3.6-35B-A3B"
  local vllm_model_id="Qwen/${model}"
  local bench_model="localvllm/${vllm_model_id}"
  local models_json

  models_json=$(curl -fsS -H "Authorization: Bearer ${OPENAI_API_KEY}" "${OPENAI_BASE_URL}/models" 2>/dev/null || true)
  if [[ "$models_json" != *"\"${vllm_model_id}\""* ]]; then
    echo "Warning: ${OPENAI_BASE_URL}/models did not list '${vllm_model_id}'."
    echo "OpenClaw will run with '${bench_model}', which should route to vLLM model '${vllm_model_id}'."
  fi

  run_bench_pair "openclaw" "$bench_model" "openclaw__${model}"
}

run_terminus() {
  load_api_keys
  use_vllm

  local model="Qwen3.6-35B-A3B"
  local task timestamp job_name

  for task in $(each_task); do
    if is_excluded "$task"; then
      echo "****Skipping excluded task: $task****"
      continue
    fi

    timestamp=$(date +"%Y-%m-%d__%H-%M-%S")
    job_name="${model}__${task}__${timestamp}"
    echo "------------------task:${task} without skills------------------------"
    uv run harbor run \
      --job-name "${job_name}" \
      -p "tasks/${task}" \
      --agent-import-path libs.terminus_agent.agents.terminus_2.harbor_terminus_2_skills:HarborTerminus2WithSkills \
      -m "openai/Qwen/${model}"
    echo "==========================================="
  done
}

case "$MODE" in
  codex)
    run_codex
    ;;
  openclaw)
    run_openclaw
    ;;
  terminus)
    run_terminus
    ;;
  *)
    echo "Usage: bash run.sh codex|openclaw|terminus"
    exit 2
    ;;
esac
