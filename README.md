# run_skillsbench

Shell runner for running the [SkillsBench](https://github.com/benchflow-ai/skillsbench) task suite with different agents.

`run.sh` is meant to be executed from the SkillsBench repository root, because it uses relative paths such as `tasks/`, `jobs/`, and `tasks/<task>/environment/skills/`.

```bash
cd ~/agents/skillsbench
bash run.sh codex
bash run.sh openclaw
bash run.sh terminus
```


## Modes

### Codex

```bash
bash run.sh codex
```

Runs every non-excluded task twice with `bench eval create`:

- with skills: `-s tasks/<task>/environment/skills/`
- without skills

Agent and model:

- agent: `codex-acp`
- model: `gpt-5.3-codex`
- jobs: `jobs/gpt-5.3-codex__withskills__...` and `jobs/gpt-5.3-codex__withoutskills__...`

This mode activates the `skillsbench` conda environment and configures the Azure OpenAI-compatible endpoint.

### OpenClaw

```bash
bash run.sh openclaw
```

Runs every non-excluded task twice with `bench eval create`:

- with skills
- without skills

Agent and model:

- agent: `openclaw`
- served vLLM model: `Qwen/Qwen3.6-35B-A3B`
- benchmark model name: `localvllm/Qwen/Qwen3.6-35B-A3B`
- jobs: `jobs/openclaw__Qwen3.6-35B-A3B__withskills__...` and `jobs/openclaw__Qwen3.6-35B-A3B__withoutskills__...`

This mode activates the `skillsbench` conda environment, points OpenAI-compatible variables at the local vLLM endpoint, and warns if `/models` does not list the expected model.

### Terminus

```bash
bash run.sh terminus
```

Runs every non-excluded task with `uv run harbor run` using the Terminus Harbor agent:

- agent import path: `libs.terminus_agent.agents.terminus_2.harbor_terminus_2_skills:HarborTerminus2WithSkills`
- model: `openai/Qwen/Qwen3.6-35B-A3B`
- job name: `Qwen3.6-35B-A3B__<task>__<timestamp>`

Unlike Codex and OpenClaw, this mode does not run a separate without-skills `bench eval create` pair. It follows the original Terminus runner behavior.

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
cd ~/agents/skillsbench
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
