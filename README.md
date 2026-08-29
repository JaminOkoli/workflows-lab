# workflows-lab

A small learning project. The point isn't the app or GCP — it's using a real,
end-to-end pipeline as an excuse to learn GitHub Actions properly: composite
actions, reusable workflows, matrix builds, manual approval gates, and the
different trigger types.

**The app:** a tiny FastAPI service.
**The target:** a GCP Compute Engine VM.
**The auth:** Workload Identity Federation (keyless — no JSON key secrets).

## The one idea to hold onto

Two GitHub Actions concepts get confused constantly. This project uses both,
back to back, for the *same* task (logging into GCP), so the difference stops
being abstract:

- **Composite action** — a reusable bundle of *steps*. Lives in
  `.github/actions/<name>/action.yml`. Used with `uses: ./.github/actions/x`
  as a single step inside a job.
- **Reusable workflow** — a reusable *entire workflow* (jobs and all). Lives
  in `.github/workflows/x.yml` with `on: workflow_call`. Called with
  `uses: ./.github/workflows/x.yml` from another workflow's `jobs:` block.

We'll build one composite action (the repeated "log into GCP" steps) and call
it from *two* different reusable workflows — so you feel exactly why each
piece exists, instead of just reading a definition.

## Repo layout (end state)

```
app/
  main.py               FastAPI: GET /, GET /health, GET /items/{id}
  requirements.txt
  requirements-dev.txt
  test_main.py          pytest smoke tests, run in CI
Dockerfile
.dockerignore
.github/
  actions/
    gcp-auth/
      action.yml         composite action: WIF login + gcloud + docker auth
  workflows/
    ci.yml                push/PR: lint + pytest (matrix'd Python versions, pip cache)
    build-and-push.yml    reusable workflow: docker build -> Artifact Registry
    deploy.yml             reusable workflow: SSH to VM, pull + restart container
    release.yml             orchestrator: calls build-and-push -> deploy
    nightly-healthcheck.yml bonus: scheduled trigger, curls /health on the VM
infra/
  setup.md               one-time manual gcloud steps (project, VM, WIF, etc.)
README.md                 you are here
```

## Follow-along steps

Work through these in order. Each stage is a working checkpoint — don't skip
ahead, since later stages reuse things earlier stages build.

- [ ] **Stage 0 — App & Docker.** Minimal FastAPI app + `Dockerfile` +
      `.dockerignore`. Build and run it locally to confirm the artifact works
      before any automation touches it. No GitHub Actions yet.
      *Verify:* `docker run` the image, `curl localhost:8000/health` → 200.

- [ ] **Stage 1 — `ci.yml`, your first workflow.** Triggers on `push` and
      `pull_request`. checkout → setup-python → install deps → `pytest`.
      Adds a Python-version matrix (3.11, 3.12) and pip caching.
      *Teaches:* `on:` triggers, jobs/steps, marketplace actions, matrix
      builds, caching.
      *Verify:* open a PR, watch both matrix legs run; second run shows a
      cache hit.

- [ ] **Stage 2 — `gcp-auth`, your first composite action.** Wraps the steps
      you're about to repeat in two workflows: WIF login (`google-github-actions/auth`)
      + `gcloud` setup + Docker-to-Artifact-Registry auth.
      *Teaches:* `runs: using: composite`, action inputs/outputs, why a local
      action beats copy-pasting the same 3 steps everywhere.
      *Verify:* nothing calls it yet — confirmed once Stage 3 uses it.

- [ ] **Stage 3 — `build-and-push.yml`, your first reusable workflow.**
      `on: workflow_call`. checkout → call `gcp-auth` → `docker build` → tag
      with the git SHA → push to Artifact Registry → expose the tag as a job
      `output`.
      *Teaches:* `workflow_call` inputs/secrets, reusable-workflow outputs,
      calling a composite action from inside a reusable workflow.
      *Verify:* trigger it, confirm the image lands in Artifact Registry.

- [ ] **Stage 4 — `deploy.yml`, second reusable workflow + an approval gate.**
      Takes the image tag as input. Calls `gcp-auth` again — same action,
      second consumer. SSHes into the VM via an IAP tunnel (port 22 never
      open to the internet) and restarts the container. Job declares
      `environment: production`, which you'll configure to require a manual
      reviewer approval.
      *Teaches:* passing data between reusable workflows, `environment:` +
      required reviewers, least-privilege network access.
      *Verify:* run shows "waiting for approval"; after approving, `curl` the
      VM's public IP on `/health`.

- [ ] **Stage 5 — `release.yml`, the orchestrator.** Triggers on push to
      `main`, on `v*` tags, and manually (`workflow_dispatch`). Job `build`
      calls `build-and-push.yml`; job `deploy` (`needs: build`) calls
      `deploy.yml`, passing in `needs.build.outputs.image_tag`. Adds a
      `concurrency:` group so a new push cancels a stale in-flight run.
      *Teaches:* `needs:`, chaining reusable workflows, `workflow_dispatch`,
      tag triggers, `concurrency:`.
      *Verify:* push to `main`, watch build → approve → deploy end-to-end;
      push again mid-run and confirm the old run gets cancelled.

- [ ] **Stage 6 — bonus round (optional).**
      `nightly-healthcheck.yml` on a `schedule:` cron, hitting the VM's
      `/health`. Plus a README note on `pull_request` vs
      `pull_request_target` (a real security gotcha), and a status badge.
      *Verify:* manually trigger it (scheduled workflows support
      `workflow_dispatch` too) and confirm it succeeds.

## GCP one-time setup

See [`infra/setup.md`](infra/setup.md) — plain `gcloud` commands (no
Terraform, to keep the scope on workflows, not IaC): create the project,
enable APIs, create the Artifact Registry repo, create the VM (no public SSH
— IAP tunnel only), create the GitHub Actions service account, and wire up
Workload Identity Federation. No JSON key is ever created.
