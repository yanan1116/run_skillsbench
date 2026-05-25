# run_skillsbench

Shell runner for running the [SkillsBench](https://github.com/benchflow-ai/skillsbench) task suite with different agents.

`run.sh` is meant to be executed from the SkillsBench repository root, because it uses relative paths such as `tasks/`, `jobs/`, and `tasks/<task>/environment/skills/`.

```bash
bash run.sh codex
bash run.sh openclaw
```

- somes of the tasks (`EXCLUDE`) are exclued from this sequential running, because they may need more api tokens from external models, such as the task of audio transcription.

- some of the tasks are inherently defective due to different causes, and they failed the oracle sanity check via  `bench eval create -t tasks/${task} -a oracle  -m oracle`

## Modes

### Codex

```bash
bash run.sh codex
```

Runs every non-excluded task twice with `bench eval create`:

- with skills: `-s tasks/<task>/environment/skills/`
- without skills

Agent and model:

- agent harness: `codex-acp`
- model: `gpt-5.3-codex`
- jobs: `jobs/gpt-5.3-codex__withskills__...` and `jobs/gpt-5.3-codex__withoutskills__...`

This mode activates the `skillsbench` conda environment and configures the Azure OpenAI-compatible endpoint.

### OpenClaw

Before running tasks, lauch the backend LLM via vllm in docker container:
```bash
sudo docker run -d --name qwen_gpus --runtime nvidia --gpus '"device=0,1"' \
      --env "HUGGING_FACE_HUB_TOKEN=hf_****" \
    -v /etc/localtime:/etc/localtime:ro \
    -v /etc/timezone:/etc/timezone:ro \
    -e TZ=America/Toronto \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    -v /etc/ssl/certs:/etc/ssl/certs:ro \
    -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    -e REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    -p 1700:1700 \
    --ipc=host \
    vllm/vllm-openai:latest \
    --model Qwen/Qwen3.6-35B-A3B \
    --api-key "yyy" \
    --port 1700 \
    --trust-remote-code \
    --gpu_memory_utilization 0.95 \
    --tensor-parallel-size 2 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder
```


```bash
bash run.sh openclaw
```

Runs every non-excluded task twice with `bench eval create`:

- with skills
- without skills

Agent and model:

- agent harness: `openclaw`
- served vLLM model: `Qwen/Qwen3.6-35B-A3B`
- benchmark model name: `localvllm/Qwen/Qwen3.6-35B-A3B`
- jobs: `jobs/openclaw__Qwen3.6-35B-A3B__withskills__...` and `jobs/openclaw__Qwen3.6-35B-A3B__withoutskills__...`

This mode activates the `skillsbench` conda environment, points OpenAI-compatible variables at the local vLLM endpoint, and warns if `/models` does not list the expected model.



## Shared Behavior

All modes:

- load `OPENAI_API_KEY` from the environment or from `~/.bashrc`
- skip the shared `EXCLUDE` task list in `run.sh`
- iterate over `tasks/` in shuffled order
- timestamp each output job with `YYYY-MM-DD__HH-MM-SS`

Codex also requires `AZURE_OPENAI_API_KEY` to be set in the environment or `~/.bashrc`.

OpenClaw and Terminus use the local vLLM endpoint:

```bash
http://10.225.68.24:1700/v1
```

## Requirements

Before running:

```bash
uv sync --locked
```

Make sure these are available:

- conda environment: `skillsbench`
- `bench` command from the SkillsBench project
- `uv`
- `curl` for OpenClaw model checking
- `OPENAI_API_KEY` in `~/.bashrc` or the current shell
- `AZURE_OPENAI_API_KEY` for Codex mode

## Usage Errors

If no mode or an unknown mode is passed, the script prints:

```bash
Usage: bash run.sh codex|openclaw|terminus
```
