# Azure DevOps CI/CD Guide

Azure Pipelines equivalent of the [`Jenkinsfile`](./Jenkinsfile): the same
build → MUnit → (Exchange) → dev → test → uat → **approval** → prod promotion,
with a `/health-check` smoke test after every deploy.

## Contents

1. [Files](#1-files)
2. [Pipeline flow](#2-pipeline-flow)
3. [One-time setup](#3-one-time-setup)
4. [Running the pipeline](#4-running-the-pipeline)
5. [Jenkins → Azure DevOps mapping](#5-jenkins--azure-devops-mapping)
6. [Hardening checklist](#6-hardening-checklist)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Files

| File | Purpose |
| --- | --- |
| `azure-pipelines.yml` | The pipeline: triggers, parameters, Build / MUnit / Exchange stages, promotion chain. |
| `.azure-pipelines/templates/deploy-stage.yml` | One deploy + smoke test stage, bound to environment `mule-<env>`. |
| `.azure-pipelines/templates/maven-setup-steps.yml` | JDK 17 + Maven repository cache. |
| `.ci/maven-settings.xml` | `settings.xml` that reads every credential from environment variables. Contains no secrets. |
| `.ci/deploy.sh` · `.ci/smoke-test.sh` · `.ci/require-env.sh` | Deploy with retry, health-check smoke test, missing-secret check. |

The `.ci/` files are shared with the GitHub Actions workflows.

---

## 2. Pipeline flow

```
 PR / push to main ─────────────►  Build ║ MUnit          (deploy stages skip)

 Manual "Run pipeline" ─────────►  Build ║ MUnit
                                        │
                                   Publish to Exchange     optional
                                        │
                                   Deploy_dev  + smoke     always
                                   Deploy_test + smoke     environment ≥ test
                                   Deploy_uat  + smoke     environment ≥ uat
                                   ⏸ mule-prod approval
                                   Deploy_prod + smoke     environment = prod
```

Stages above the chosen environment are not compiled into the run at all, so
the run view only shows the stages that will execute.

---

## 3. One-time setup

### 3.1 Anypoint connected app

Create a connected app (client credentials) as in
[Jenkins-README.md § 4.1](./Jenkins-README.md#41-create-an-anypoint-connected-app).

### 3.2 Variable groups

**Pipelines → Library → + Variable group.** Tick the 🔒 icon for every secret.

**`mule-common`**

| Variable | Secret | Required | Value |
| --- | --- | --- | --- |
| `ANYPOINT_CLIENT_ID` | ✅ | ✅ | Connected app client id |
| `ANYPOINT_CLIENT_SECRET` | ✅ | ✅ | Connected app client secret |
| `MUNIT_ENFORCE_COVERAGE` | – | – | `true` makes PR/CI runs fail below pom.xml thresholds. Default off (template ≈ 24%). |

**`mule-dev`, `mule-test`, `mule-uat`, `mule-prod`** (one group per environment)

| Variable | Secret | Required | Value |
| --- | --- | --- | --- |
| `MULE_ENC_KEY` | ✅ | ✅ | Key for `properties/<env>-secure.yaml` (16, 24 or 32 chars) |
| `APP_BASE_URL` | – | – | e.g. `https://my-app-dev.uk-e1.cloudhub.io/api`. Smoke test skipped when unset. |
| `API_ID` | – | – | Only once API autodiscovery is enabled |
| `PLATFORM_CLIENT_ID` / `PLATFORM_CLIENT_SECRET` | ✅ | – | Only once API autodiscovery is enabled |

> A variable in `mule-<env>` with the same name as one in `mule-common` wins.
> Add `ANYPOINT_CLIENT_ID` / `ANYPOINT_CLIENT_SECRET` to `mule-prod` to give
> production its own connected app.
>
> Variable groups can be **linked to Azure Key Vault** instead of holding
> the values directly — recommended for production.
>
> Groups and environments are project-wide. If several Mule applications share
> one project with different keys, prefix the names per application and update
> `mule-common` / `mule-${{ parameters.environment }}` in the YAML.

### 3.3 Environments and approvals

**Pipelines → Environments → New environment** (resource: *None*) — create
`mule-dev`, `mule-test`, `mule-uat`, `mule-prod`.

On **`mule-prod` → ⋮ → Approvals and checks** — the Jenkins
`release-approvers` gate:

| Check | Setting |
| --- | --- |
| **Approvals** | Your release approvers group · *Allow approvers to approve their own runs* **off** · Timeout **24 hours** (same as Jenkins) |
| **Branch control** | Allowed branches `refs/heads/main` · *Verify branch protection* on |
| **Exclusive lock** | Add on every environment — one deploy at a time per environment |

Recommended on `mule-uat`: branch control to `refs/heads/main`.

### 3.4 Create the pipeline

1. **Pipelines → New pipeline** → your repository (GitHub or Azure Repos).
2. **Existing Azure Pipelines YAML file** → branch `main`, path `/azure-pipelines.yml`.
3. **Save** (not Run).
4. Run it once manually. Azure DevOps asks to **Permit** access to each
   variable group and environment the first time — approve them, or grant
   access up front under each resource's **Pipeline permissions**.

### 3.5 Pull request validation

- **GitHub repository:** the `pr:` trigger in the YAML already covers it. Make
  the pipeline a required status check in GitHub branch protection.
- **Azure Repos:** `pr:` is ignored. Add **Repos → Branches → main → Branch
  policies → Build validation** → this pipeline.

---

## 4. Running the pipeline

**Pipelines → (this pipeline) → Run pipeline**, choose the branch, then:

| Parameter | Default | Effect |
| --- | --- | --- |
| Highest environment | `dev` | Lower environments deploy first. |
| Skip MUnit | `false` | Emergency hotfix only. |
| Enforce coverage | `true` | Passes `-Dmunit.coverage.failBuild=true`. **Untick on the first run** of the untouched template. |
| Publish to Exchange | `false` | Also runs `mvn deploy` to publish to Exchange. |

Parameters apply to **manual** runs. PR and push-to-main runs only build and
test, whatever the defaults say.

When `Deploy_prod` is reached, approvers are notified and the stage shows
**Review**. Nothing runs against production until approved; after 24 hours the
approval times out and the stage fails.

Results: **Tests** tab (MUnit) · **Artifacts** → `munit-reports-attempt-N` →
`coverage/summary.html` · `mule-application` (the jar).

---

## 5. Jenkins → Azure DevOps mapping

| Jenkinsfile | Azure DevOps |
| --- | --- |
| Build parameters | Runtime `parameters` in `azure-pipelines.yml` |
| `maven-settings` managed file | `.ci/maven-settings.xml` + variable groups mapped into `env:` |
| `input(submitter: 'release-approvers')`, 24 h | `mule-prod` environment → Approvals (24 h timeout) |
| `disableConcurrentBuilds()` | Exclusive lock checks + `lockBehavior: sequential` |
| `retry(2)` deploy / `retry(3)` smoke | `DEPLOY_ATTEMPTS=2` / `SMOKE_ATTEMPTS=5` in `.ci/*.sh` |
| `APP_BASE_URL_<ENV>` | `APP_BASE_URL` in `mule-<env>` |
| `junit` + `publishHTML` | `PublishTestResults@2` (Tests tab) + `munit-reports` artifact |
| `archiveArtifacts` | `mule-application` pipeline artifact |
| `MAVEN_LOCAL_REPO` in workspace | `Cache@2` on `$(Pipeline.Workspace)/.m2/repository` |

Like the Jenkinsfile, each deploy runs `mvn deploy -P<env> -DmuleDeploy` from the
same commit, so every environment receives the same `artifactId:version`.

---

## 6. Hardening checklist

- [ ] All secrets marked 🔒 (or sourced from Key Vault); secret variables are only visible to steps that map them in `env:`.
- [ ] `mule-prod`: approvals (no self-approval), branch control `main`, exclusive lock.
- [ ] Variable group and environment **Pipeline permissions** restricted to this pipeline, not "open access".
- [ ] **Project settings → Pipelines → Settings**: *Limit job authorization scope to current project*, *Protect access to repositories in YAML pipelines*.
- [ ] Separate connected app per environment with only that environment's scopes.
- [ ] Self-hosted agents need JDK 17 (`JAVA_HOME_17_X64`), Maven 3.8+, `bash`, `curl`.

---

## 7. Troubleshooting

| Problem | Cause | Fix |
| --- | --- | --- |
| *Variable group was not found or is not authorized* when queuing | Group missing, misnamed, or not permitted | Create it (§ 3.2) with the exact name; **Permit** on the run page. |
| `Missing required configuration: MULE_ENC_KEY` | Variable missing from `mule-<env>` (an unresolved `$(MULE_ENC_KEY)` counts as missing) | Add it to that group with the exact name. |
| Deploy stages **Skipped** | PR / CI run — by design | Use **Run pipeline**. |
| Stage stuck *Waiting* | Approval pending or exclusive lock held | Approve under the stage's **Review**; check other runs on the environment. |
| *No agent found in pool Azure Pipelines* / parallelism error | No hosted parallel jobs granted | Request the free grant or use a self-hosted pool (change `pool:`). |
| `401 Unauthorized` | Wrong connected app credentials or scopes | Re-check `mule-common` (or the `mule-<env>` override). |
| MUnit fails with *coverage is below defined limit* | Enforce coverage on and coverage < 70% | Untick it or lower `munit.coverage.*` in `pom.xml`. |
| Branch control check fails on prod | Run queued from a non-main branch | Run from `main`. |
| Smoke test fails but deploy succeeded | App unhealthy, wrong URL, or slow start | Check Runtime Manager logs; URL must end in `/api`; raise `SMOKE_ATTEMPTS`. |
