# GitHub Actions CI/CD Guide

GitHub Actions equivalent of the [`Jenkinsfile`](./Jenkinsfile): the same
build → MUnit → (Exchange) → dev → test → uat → **approval** → prod promotion,
with a `/health-check` smoke test after every deploy.

## Contents

1. [Files](#1-files)
2. [Pipeline flow](#2-pipeline-flow)
3. [One-time setup](#3-one-time-setup)
4. [Running a deployment](#4-running-a-deployment)
5. [Jenkins → GitHub Actions mapping](#5-jenkins--github-actions-mapping)
6. [Hardening checklist](#6-hardening-checklist)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Files

| File | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Build + MUnit on every PR to `main` and every push to `main`. Deploys nothing. |
| `.github/workflows/deploy.yml` | Manual promotion pipeline (the Jenkinsfile equivalent). |
| `.github/workflows/_deploy-environment.yml` | Reusable workflow: deploy one environment + smoke test. |
| `.github/dependabot.yml` | Weekly PR keeping action versions current. |
| `.ci/maven-settings.xml` | `settings.xml` that reads every credential from environment variables. Contains no secrets. |
| `.ci/deploy.sh` | `mvn deploy -P<env> -DmuleDeploy` with retry. |
| `.ci/smoke-test.sh` | `GET <APP_BASE_URL>/health-check` must return 200 with `"status": "UP"`. |
| `.ci/require-env.sh` | Fails early, by name, when a secret is missing. |
| `.ci/munit-summary.sh` | Renders MUnit results into the job summary. |

The `.ci/` files are shared with the Azure DevOps pipeline.

---

## 2. Pipeline flow

```
 CI (ci.yml) ── pull request / push to main
 ┌──────────────────────────────────────────┐
 │ Build & MUnit   mvn clean package        │  job summary + munit-reports artifact
 └──────────────────────────────────────────┘

 Deploy (deploy.yml) ── Actions ▸ Deploy ▸ Run workflow
 ┌───────────┐   ┌───────────┐
 │ Build     │   │ MUnit     │   run in parallel; MUnit skippable
 └─────┬─────┘   └─────┬─────┘
       └───────┬───────┘
       ┌───────▼────────────┐
       │ Publish to Exchange│   optional
       └───────┬────────────┘
       ┌───────▼───────┐
       │ dev  + smoke  │   always
       ├───────────────┤
       │ test + smoke  │   environment ≥ test
       ├───────────────┤
       │ uat  + smoke  │   environment ≥ uat
       ├───────────────┤
       │ ⏸ approval    │   prod environment required reviewers
       │ prod + smoke  │   environment = prod, main branch only
       └───────────────┘
```

---

## 3. One-time setup

### 3.1 Anypoint connected app

Create a connected app (client credentials) exactly as in
[Jenkins-README.md § 4.1](./Jenkins-README.md#41-create-an-anypoint-connected-app):
Exchange Contributor, Runtime Manager and the environments you deploy to.

### 3.2 Repository secrets and variables

**Settings → Secrets and variables → Actions**

| Name | Type | Required | Value |
| --- | --- | --- | --- |
| `ANYPOINT_CLIENT_ID` | Secret | ✅ | Connected app client id |
| `ANYPOINT_CLIENT_SECRET` | Secret | ✅ | Connected app client secret |
| `MUNIT_ENFORCE_COVERAGE` | Variable | – | `true` makes **CI** fail below the pom.xml thresholds. Default off: the untouched template sits near 24%. |

### 3.3 Environments

**Settings → Environments → New environment** — create `dev`, `test`, `uat`
and `prod`. The names must match exactly: they are also the `pom.xml` profile
ids.

On **each** environment:

| Name | Type | Required | Value |
| --- | --- | --- | --- |
| `MULE_ENC_KEY` | Secret | ✅ | Key that decrypts `properties/<env>-secure.yaml` (16, 24 or 32 chars) |
| `APP_BASE_URL` | Variable | – | e.g. `https://my-app-dev.uk-e1.cloudhub.io/api`. Smoke test is skipped when unset. |
| `API_ID` | Secret | – | Only once API autodiscovery is enabled in `global.xml` |
| `PLATFORM_CLIENT_ID` / `PLATFORM_CLIENT_SECRET` | Secret | – | Only once API autodiscovery is enabled |

> An environment secret **overrides** a repository secret with the same name.
> To give production its own connected app, add `ANYPOINT_CLIENT_ID` /
> `ANYPOINT_CLIENT_SECRET` to the `prod` environment.

On **`prod`** — this is the Jenkins `release-approvers` gate:

| Protection rule | Setting |
| --- | --- |
| Required reviewers | Your release approvers (user or team) |
| Prevent self-review | ✅ |
| Deployment branches and tags | **Selected branches** → `main` |

Recommended on `uat` too: deployment branches → `main`.

> Required reviewers on **private** repositories depend on your GitHub plan —
> check GitHub's documentation on deployment environments before relying on
> the gate.

### 3.4 Branch protection

**Settings → Branches → Branch protection rule** for `main`:
require the **Build & MUnit** status check to pass before merging.

---

## 4. Running a deployment

**Actions → Deploy → Run workflow**, choose the branch (`main` for anything
beyond `test`), then:

| Input | Default | Effect |
| --- | --- | --- |
| `environment` | `dev` | Highest environment to promote to. Lower ones deploy first. |
| `skip_tests` | `false` | Skips the MUnit job. Emergency hotfix only. |
| `enforce_coverage` | `true` | Passes `-Dmunit.coverage.failBuild=true`. **Untick on the first run** of the untouched template. |
| `publish_to_exchange` | `false` | Also runs `mvn deploy` to publish the artifact to Exchange. |

| Scenario | `environment` | What happens |
| --- | --- | --- |
| Dev only | `dev` | Build + MUnit → dev → smoke |
| Up to test | `test` | … → dev → test, each smoke tested |
| Up to UAT | `uat` | … → dev → test → uat |
| Production | `prod` | … → dev → test → uat → **approval** → prod → smoke |

When the run reaches `prod`, reviewers get a notification and the run page
shows **Review deployments**. Nothing runs against production until approved.

---

## 5. Jenkins → GitHub Actions mapping

| Jenkinsfile | GitHub Actions |
| --- | --- |
| `ENVIRONMENT` / `SKIP_TESTS` / `ENFORCE_COVERAGE` / `PUBLISH_TO_EXCHANGE` parameters | `workflow_dispatch` inputs of `deploy.yml` |
| `maven-settings` managed file | `.ci/maven-settings.xml` + secrets as environment variables |
| `input(submitter: 'release-approvers')`, 24 h timeout | `prod` environment required reviewers (a pending approval expires after 30 days; reject stale runs) |
| `disableConcurrentBuilds()` | `concurrency: deploy-<repo>`, `cancel-in-progress: false` |
| `retry(2)` on deploy / `retry(3)` on smoke test | `DEPLOY_ATTEMPTS=2` / `SMOKE_ATTEMPTS=5` in `.ci/*.sh` |
| `APP_BASE_URL_<ENV>` global variables | `APP_BASE_URL` variable on each environment |
| `junit` + `publishHTML` | Job summary table + `munit-reports` artifact (`coverage/summary.html`) |
| `archiveArtifacts` | `mule-application` artifact, kept 30 days |
| `timeout(60 min)` | `timeout-minutes` per job |
| `post { failure { … } }` | `Result` job — add Slack/Teams notification there |

Like the Jenkinsfile, each deploy runs `mvn deploy -P<env> -DmuleDeploy` from the
same commit, so every environment receives the same `artifactId:version`.

---

## 6. Hardening checklist

- [ ] Pin every `uses:` to a full commit SHA (`actions/checkout@<sha> # v4`). Dependabot keeps pinned SHAs updated.
- [ ] **Settings → Actions → General**: allow only GitHub-owned actions — the workflows use nothing else.
- [ ] **Settings → Actions → General → Workflow permissions**: *Read repository contents* (the workflows request nothing more).
- [ ] `prod` environment: required reviewers, prevent self-review, `main` only.
- [ ] Production is also guarded inside `deploy.yml`: a `prod` run from any ref other than `refs/heads/main` fails in the Build job.
- [ ] Use a separate connected app per environment (environment secrets) with only that environment's scopes.
- [ ] Rotate `ANYPOINT_CLIENT_SECRET` and `MULE_ENC_KEY` on a schedule; secrets are masked in logs.

---

## 7. Troubleshooting

| Problem | Cause | Fix |
| --- | --- | --- |
| `Missing required configuration: ANYPOINT_CLIENT_ID …` | Secret not set, or a PR from a fork (forks get no secrets) | Add the repository secrets (§ 3.2). Fork PRs cannot build against Exchange; push the branch to the repo instead. |
| `Missing required configuration: MULE_ENC_KEY` in a deploy job | Environment not created or secret on the wrong scope | Add `MULE_ENC_KEY` to that environment (§ 3.3) — not only as a repository secret. |
| `401 Unauthorized` resolving dependencies or deploying | Wrong connected app id/secret or missing scopes | Re-check the secrets and connected app scopes for that environment. |
| MUnit fails with *coverage is below defined limit* | `enforce_coverage` is on and coverage < 70% | Untick `enforce_coverage`, or lower `munit.coverage.*` in `pom.xml`. |
| `Production deploys must run from refs/heads/main` | `prod` run from another branch | Merge to `main` and run from `main`. |
| Deploy jobs never start, status *Waiting* | Required reviewers pending | A reviewer approves under **Review deployments**. |
| test/uat/prod jobs show *skipped* | Target `environment` lower than that stage, or an earlier job failed | Expected — check the first failed job. |
| Smoke test *skipping* | `APP_BASE_URL` not set on that environment | Add the variable (§ 3.3). |
| Smoke test fails but deploy succeeded | App unhealthy, wrong URL, or startup slower than 5 × 15 s | Check Runtime Manager logs; verify the URL ends in `/api`; raise `SMOKE_ATTEMPTS`. |
| App starts then fails: *could not decrypt* | `MULE_ENC_KEY` differs from the key used to encrypt that environment's secure YAML | Use the right key; `deploy.sh` warns when its length is not 16/24/32. |
