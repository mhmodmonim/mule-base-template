# Jenkins CI/CD Pipeline Guide for MuleSoft Project

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Jenkins Server Setup](#2-jenkins-server-setup)
3. [Required Jenkins Plugins](#3-required-jenkins-plugins)
4. [Configure Jenkins Credentials](#4-configure-jenkins-credentials)
5. [Configure a Build Agent (Node)](#5-configure-a-build-agent-node)
6. [Create the Pipeline Job](#6-create-the-pipeline-job)
7. [Project File Structure](#7-project-file-structure)
8. [Jenkinsfile Walkthrough](#8-jenkinsfile-walkthrough)
9. [Running the Pipeline](#9-running-the-pipeline)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

Before you begin, make sure you have:

| Requirement              | Details                                                        |
| ------------------------ | -------------------------------------------------------------- |
| Jenkins Server           | Version 2.387+ (LTS recommended)                              |
| Java (on build agent)    | JDK 8 or JDK 11 (required by Mule 4.x Maven builds)          |
| Maven (on build agent)   | 3.8.x or 3.9.x                                                |
| Anypoint Platform        | An Anypoint Connected App with **CloudHub** deployment scope   |
| Git / GitHub             | Your MuleSoft project in a Git repository                      |
| Network Access           | Build agent must reach `maven.anypoint.mulesoft.com` and `anypoint.mulesoft.com` |

---

## 2. Jenkins Server Setup

### 2.1 Install Jenkins (if not already installed)

**On Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install fontconfig openjdk-11-jre
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
```

**On Windows:**
1. Download the Jenkins MSI installer from the official Jenkins site.
2. Run the installer and follow the wizard.
3. Access Jenkins at `http://localhost:8080`.

### 2.2 Complete the Setup Wizard

1. Navigate to `http://<your-jenkins-host>:8080`.
2. Paste the initial admin password from the console/log.
3. Choose **Install suggested plugins**.
4. Create your first admin user.

---

## 3. Required Jenkins Plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:

| Plugin                        | Purpose                                         |
| ----------------------------- | ----------------------------------------------- |
| **Pipeline**                  | Core declarative pipeline support (usually pre-installed) |
| **Pipeline: Stage View**      | Visual stage progress on the job page            |
| **Git**                       | Git SCM integration                              |
| **Credentials Binding**       | Injects `credentials()` into pipeline env vars   |
| **JUnit**                     | Publishes MUnit/Surefire test results            |
| **HTML Publisher**            | Publishes MUnit coverage HTML reports            |
| **Workspace Cleanup**         | `cleanWs()` step support                         |
| **Timestamper**               | `timestamps()` option in pipeline                |
| **Config File Provider**      | Manages `settings.xml` centrally; injects it via `configFileProvider` step |

After installing, restart Jenkins when prompted.

---

## 4. Configure Jenkins Credentials

### 4.1 Create an Anypoint Connected App

1. Log in to **Anypoint Platform → Access Management → Connected Apps**.
2. Click **Create app**.
3. Select **App acts on its own behalf (client credentials)**.
4. Grant these scopes:
   - `CloudHub Organization Admin` or `CloudHub Developer` (for each environment)
   - `Design Center Developer` (if needed)
   - `Exchange Contributor` (if publishing to Exchange)
5. Note the **Client ID** and **Client Secret**.

### 4.2 Add Credentials to Jenkins

1. Go to **Manage Jenkins → Credentials → System → Global credentials**.
2. Click **Add Credentials**.
3. Fill in:

| Field          | Value                                      |
| -------------- | ------------------------------------------ |
| Kind           | **Username with password**                 |
| Scope          | Global                                     |
| Username       | `~~~Client~~~` (literal, for a connected app) |
| Password       | `<clientId>~?~<clientSecret>`              |
| ID             | `anypoint-connected-app`                   |
| Description    | Anypoint Platform Connected App Credentials |

4. Click **Create**.

> **Important:** The credential ID **must** match `anypoint-connected-app` — it
> is what the managed `settings.xml` binds to the `anypoint-exchange-v3` server.
> This credential authenticates **dependency resolution and Exchange publishing**.
> The *deployment* uses the `anypoint.connectedApp.*` Maven properties in the
> same managed file (Section 4.3); both are needed.

### 4.3 Configure Managed Maven `settings.xml` (Config File Provider)

The Jenkinsfile uses the **Config File Provider** plugin to inject a managed `settings.xml` into every Maven invocation. This avoids placing credentials on the agent's filesystem.

1. Go to **Manage Jenkins → Managed files → Add a new Config**.
2. Select **Maven settings.xml**, click **Submit**.
3. Set:

| Field  | Value              |
| ------ | ------------------ |
| ID     | `maven-settings`   |
| Name   | MuleSoft Maven Settings |

4. Paste the following content. The `<properties>` block is the part that is
   easy to forget: `mule-maven-plugin` reads the connected-app credentials and
   the encryption key from Maven properties, **not** from `<servers>`, so the
   server-credentials mapping alone is not enough to deploy.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
    <servers>
        <server>
            <id>anypoint-exchange-v3</id>
            <!-- username/password injected by Config File Provider -->
        </server>
    </servers>

    <profiles>
        <profile>
            <id>anypoint-credentials</id>
            <properties>
                <!-- Consumed by <cloudhub2Deployment> in pom.xml -->
                <anypoint.connectedApp.clientId>CONNECTED_APP_CLIENT_ID</anypoint.connectedApp.clientId>
                <anypoint.connectedApp.clientSecret>CONNECTED_APP_CLIENT_SECRET</anypoint.connectedApp.clientSecret>

                <!-- Decrypts ![...] values in properties/<env>-secure.yaml -->
                <enc.key>SIXTEEN_CHAR_KEY</enc.key>

                <!-- Only needed once API autodiscovery is enabled in global.xml -->
                <api.id>API_INSTANCE_ID</api.id>
                <anypoint.platform.client_id>PLATFORM_CLIENT_ID</anypoint.platform.client_id>
                <anypoint.platform.client_secret>PLATFORM_CLIENT_SECRET</anypoint.platform.client_secret>
            </properties>
        </profile>
    </profiles>

    <activeProfiles>
        <activeProfile>anypoint-credentials</activeProfile>
    </activeProfiles>
</settings>
```

> The repository URLs are declared in `pom.xml`, so they do not need to be
> repeated here. `settings-template.xml` in the repo root is the same file for
> local development — keep the two in sync.

5. Under **Server Credentials**, map each `<server>` ID to the Jenkins credential:

| Server ID               | Credentials                |
| ----------------------- | -------------------------- |
| `anypoint-exchange-v3`  | `anypoint-connected-app`   |

For a connected app, the credential's **username** is the literal string
`~~~Client~~~` and the **password** is `<clientId>~?~<clientSecret>`.

6. Click **Submit**.

> **Important:** The file ID **must** be `maven-settings` — this is the ID referenced in the Jenkinsfile's `configFileProvider` steps. Credentials are encrypted in Jenkins and injected at build time; they never appear in the Jenkinsfile or console log.

### 4.4 (Optional) GitHub Credentials

If your repository is private:

1. Create a **GitHub Personal Access Token** with `repo` scope.
2. In Jenkins, add a new credential:

| Field    | Value                                |
| -------- | ------------------------------------ |
| Kind     | **Username with password**           |
| Username | `<your GitHub username>`             |
| Password | `<your GitHub PAT>`                  |
| ID       | `github-credentials`                 |

---

## 5. Configure a Build Agent (Node)

The Jenkinsfile uses `agent { label 'mule-builder' }`. You need a node with that label.

### Option A: Use the Built-in Node (simple setup)

1. Go to **Manage Jenkins → Nodes → Built-In Node → Configure**.
2. In **Labels**, add: `mule-builder`
3. Save.

### Option B: Add a Dedicated Agent

1. Go to **Manage Jenkins → Nodes → New Node**.
2. Name: `mule-agent-1`, select **Permanent Agent**.
3. Configure:

| Setting            | Value                          |
| ------------------ | ------------------------------ |
| Labels             | `mule-builder`                 |
| Remote root dir    | `/home/jenkins/agent`          |
| Launch method      | Launch agent via SSH / JNLP    |
| # of executors     | 2                              |

4. Save and connect the agent.

### Agent Software Requirements

On the agent machine, ensure these are installed and on `PATH`:

```bash
# Verify Java
java -version    # Must be JDK 8 or 11

# Verify Maven
mvn -version     # Must be 3.8+

# Verify Git
git --version
```

> **Note:** Maven `settings.xml` is managed centrally via the **Config File Provider** plugin (see [Section 4.3](#43-configure-managed-maven-settingsxml-config-file-provider)). You do **not** need to place a `settings.xml` on the build agent manually.

---

## 6. Create the Pipeline Job

### 6.1 Create a New Pipeline

1. From Jenkins Dashboard, click **New Item**.
2. Enter a name (e.g., `my-mule-app-pipeline`).
3. Select **Pipeline**, then click **OK**.

### 6.2 Configure the Pipeline Source

Under the **Pipeline** section at the bottom:

| Setting                | Value                                                       |
| ---------------------- | ----------------------------------------------------------- |
| Definition             | **Pipeline script from SCM**                                |
| SCM                    | **Git**                                                     |
| Repository URL         | `https://github.com/YOUR_ORG/YOUR_REPO.git`                |
| Credentials            | Select your `github-credentials` (if private repo)          |
| Branch Specifier       | `*/main` (or your default branch)                           |
| Script Path            | `Jenkinsfile`                                               |

> **Note:** Rename `Jenkinsfile.txt` to `Jenkinsfile` (no extension) and place it in the **root** of your Git repository.

### 6.3 (Optional) Enable Webhook Trigger

Under **Build Triggers**, check:
- **GitHub hook trigger for GITScm polling**

Then in your GitHub repo:
1. Go to **Settings → Webhooks → Add webhook**.
2. Payload URL: `http://<your-jenkins-host>:8080/github-webhook/`
3. Content type: `application/json`
4. Events: **Just the push event**

---

## 7. Project File Structure

```
my-mule-app/
├── Jenkinsfile                       ← Pipeline definition
├── pom.xml                           ← Deployment profiles: dev / test / uat / prod
├── mule-artifact.json                ← Runtime + secureProperties declaration
├── settings-template.xml             ← Local copy of the managed settings.xml
├── src/
│   ├── main/
│   │   ├── build-info/               ← Maven-filtered build metadata
│   │   ├── mule/                     ← Flows (main, global, error handler, impl)
│   │   └── resources/
│   │       ├── api/                  ← RAML contract
│   │       ├── properties/           ← <env>.yaml + <env>-secure.yaml
│   │       └── log4j2.xml
│   └── test/
│       ├── munit/                    ← MUnit suites, incl. api-e2e-test-suite.xml
│       └── resources/log4j2-test.xml
└── .github/pull_request_template.md
```

### Key `pom.xml` Configuration

The Jenkinsfile activates one Maven profile per environment (`-Pdev`, `-Ptest`,
`-Puat`, `-Pprod`). Unlike older layouts, the profiles here **only override
Maven properties** — there is a single `mule-maven-plugin` configuration in
`<build>` that consumes them:

```xml
<profile>
    <id>uat</id>
    <properties>
        <deployment.env>uat</deployment.env>
        <anypoint.environment>UAT</anypoint.environment>
        <cloudhub.replicas>2</cloudhub.replicas>
        <cloudhub.vCores>0.2</cloudhub.vCores>
    </properties>
</profile>
```

Adding an environment therefore means adding a profile plus the two matching
files `src/main/resources/properties/<env>.yaml` and `<env>-secure.yaml`. There
is no plugin configuration to duplicate.

`<connectedAppClientId>` / `<connectedAppClientSecret>` in the shared
`<cloudhub2Deployment>` block resolve from the managed `settings.xml`
properties (see [Section 4.3](#43-configure-managed-maven-settingsxml-config-file-provider)).

---

## 8. Jenkinsfile Walkthrough

### Pipeline Flow

The pipeline builds **once** and promotes that same artifact upward. Choosing
`uat` deploys dev, then test, then uat — each followed by a smoke test against
`/health-check`.

```
┌──────────────────────┐
│  Build               │  mvn clean package -DskipMunitTests
└──────────┬───────────┘  archives target/*-mule-application.jar
           │
┌──────────▼───────────┐
│  MUnit               │  mvn test -Dmunit.coverage.failBuild=<param>
└──────────┬───────────┘  JUnit XML + coverage HTML
           │
┌──────────▼───────────┐
│  Publish to Exchange │  optional (PUBLISH_TO_EXCHANGE)
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│  Deploy dev  + smoke │  runs for every ENVIRONMENT choice
└──────────┬───────────┘
┌──────────▼───────────┐
│  Deploy test + smoke │  runs if ENVIRONMENT is test, uat or prod
└──────────┬───────────┘
┌──────────▼───────────┐
│  Deploy uat  + smoke │  runs if ENVIRONMENT is uat or prod
└──────────┬───────────┘
┌──────────▼───────────┐
│  Approval gate       │  prod only — 24h timeout, `release-approvers`
└──────────┬───────────┘
┌──────────▼───────────┐
│  Deploy prod + smoke │
└──────────────────────┘
```

### Parameters

| Parameter             | Default | Effect |
| --------------------- | ------- | ------ |
| `ENVIRONMENT`         | `dev`   | Highest environment to promote to. Lower ones deploy first. |
| `SKIP_TESTS`          | `false` | Skips the MUnit stage. Emergency hotfix only. |
| `ENFORCE_COVERAGE`    | `true`  | Passes `-Dmunit.coverage.failBuild=true`, turning the coverage report into a gate. |
| `PUBLISH_TO_EXCHANGE` | `false` | Also runs `mvn deploy` to publish the artifact to Exchange. |

### Key Behaviours

| Feature | Details |
| ------- | ------- |
| **Promotion order** | `envRank()` maps dev=1, test=2, uat=3, prod=4; a stage runs when the chosen target ranks at or above it. |
| **Maven settings** | Injected per step by `withMavenSettings` (`configFileProvider`, file id `maven-settings`). |
| **Skipping MUnit** | `-DskipMunitTests`. **`-DskipTests` does not skip MUnit** — that was a bug in the previous pipeline. |
| **Local repo** | Pinned to `${WORKSPACE}/.m2repository` so concurrent jobs cannot corrupt a shared cache. |
| **Smoke tests** | Each deploy is followed by a `GET /health-check` that must return 200 with `"status": "UP"`. Skipped with a message when `APP_BASE_URL_<ENV>` is not set. |
| **Retry on deploy** | Each deploy retries up to 2 times; each smoke test up to 3. |
| **Application name** | Comes from `cloudhub.appName` in `pom.xml` (`<artifactId>-<env>`, no suffix for prod), not from a Jenkins parameter — one source of truth. |
| **Build name** | Set to `#<n> <artifact>:<version> -> <env>` so the build history is readable. |
| **Concurrent builds** | Disabled. |
| **Timeout** | 60 min pipeline, 24 h for the production approval. |

### Smoke test configuration

Set these as Jenkins global environment variables
(**Manage Jenkins → System → Global properties → Environment variables**):

| Name                | Example |
| ------------------- | ------- |
| `APP_BASE_URL_DEV`  | `https://my-app-dev.uk-e1.cloudhub.io/api` |
| `APP_BASE_URL_TEST` | `https://my-app-test.uk-e1.cloudhub.io/api` |
| `APP_BASE_URL_UAT`  | `https://my-app-uat.uk-e1.cloudhub.io/api` |
| `APP_BASE_URL_PROD` | `https://my-app.uk-e1.cloudhub.io/api` |

If a variable is absent the smoke test logs that it is skipping and the
pipeline continues — so you can adopt them one environment at a time.

---

## 9. Running the Pipeline

### First Run

1. Open the pipeline job in Jenkins.
2. Click **Build with Parameters**.
3. Select:
   - **ENVIRONMENT**: `dev` (start here for the first run)
   - **SKIP_TESTS**: unchecked
   - **ENFORCE_COVERAGE**: uncheck it for the first run — the untouched
     template sits around 24% because most of the global error handler is
     unreachable until you wire up real backends.
4. Click **Build**.

> **Note:** The first run will also register the parameters in Jenkins. If you don't see **Build with Parameters**, click **Build Now** once — it will fail but register the parameters for subsequent runs.

### Deploying Through Environments

| Scenario        | ENVIRONMENT param | What happens                                            |
| --------------- | ----------------- | ------------------------------------------------------- |
| Dev only        | `dev`             | Build → MUnit → dev → smoke                             |
| Up to Test      | `test`            | … → dev → smoke → test → smoke                          |
| Up to UAT       | `uat`             | … → dev → test → uat, each smoke tested                 |
| Full production | `prod`            | … → dev → test → uat → **approval** → prod → smoke      |

### Approving a Production Deployment

1. When the pipeline reaches the **Approval for Production** stage, it pauses.
2. Members of the `release-approvers` group will see an **Approve** / **Abort** prompt.
3. Click **Approve** to proceed or **Abort** to cancel.
4. If no one approves within 24 hours, the build times out and fails.

### Setting Up the Approvers Group

1. Go to **Manage Jenkins → Security → Manage Roles** (requires Role-Based Authorization Strategy plugin).
2. Create a role or group called `release-approvers`.
3. Add the users who are authorized to approve production deployments.

**Alternative (without role plugin):** Change `submitter: 'release-approvers'` in the Jenkinsfile to a comma-separated list of Jenkins usernames:
```groovy
input message: "Deploy to PRODUCTION?", ok: 'Approve', submitter: 'admin,john,jane'
```

---

## 10. Troubleshooting

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `mvn: command not found` | Maven not installed on agent | Install Maven on the agent and add to `PATH` |
| `Could not resolve dependencies` | Missing MuleSoft repos or wrong settings | Verify the managed `settings.xml` in **Manage Jenkins → Managed files** has the correct repository URLs and that its ID is `maven-settings` (see Section 4.3) |
| `401 Unauthorized` on deploy | Wrong or missing server credentials | In **Managed files → maven-settings**, verify the **Server Credentials** mappings bind `anypoint-exchange-v3` and `mulesoft-releases` to `anypoint-connected-app` |
| `No such configFile` error | Config File Provider not set up | Install the **Config File Provider** plugin and create a managed file with ID `maven-settings` (see Section 4.3) |
| `No agent with label mule-builder` | No node has the label | Add `mule-builder` label to a node (see Section 5) |
| Parameters not showing | First run needed | Run the pipeline once to register parameters |
| `cleanWs` fails | Plugin missing | Install the **Workspace Cleanup** plugin |
| `publishHTML` fails | Plugin or report missing | Install the **HTML Publisher** plugin; the Jenkinsfile uses `allowMissing: true` so a missing report dir will not fail the build |
| MUnit coverage report empty | MUnit coverage not configured | Add `<coverage>` config in `pom.xml` under `munit-maven-plugin` |
| Deploy succeeds but wrong env config | Maven profile mismatch | Ensure `pom.xml` has `<profile>` entries with `<id>dev</id>`, `<id>test</id>`, `<id>uat</id>`, `<id>prod</id>` matching the `-P<env>` flag |
| MUnit runs even though tests were "skipped" | Used `-DskipTests` | MUnit's switch is `-DskipMunitTests`; `-DskipTests` only affects Surefire |
| `Couldn't find configuration property value for key ${...}` | The property exists in `<env>.yaml` for one environment only | Every property must exist in all four `properties/<env>.yaml` files |
| App deploys but returns 500 on every call | `enc.key` not passed, or a YAML value is unquoted | Mule's YAML provider accepts strings only — quote every value, booleans included |
| Smoke test skipped | `APP_BASE_URL_<ENV>` not set | Add it under Manage Jenkins → System → Global properties |

### MUnit coverage

Coverage is already configured in `pom.xml` and reported on every build. It is
a **gate** only when `-Dmunit.coverage.failBuild=true`, which the Jenkinsfile
passes from the `ENFORCE_COVERAGE` parameter:

```xml
<coverage>
    <runCoverage>true</runCoverage>
    <failBuild>${munit.coverage.failBuild}</failBuild>
    <requiredApplicationCoverage>${munit.coverage.application}</requiredApplicationCoverage>
    <requiredResourceCoverage>${munit.coverage.resource}</requiredResourceCoverage>
    <requiredFlowCoverage>${munit.coverage.flow}</requiredFlowCoverage>
    <formats>
        <format>html</format>
        <format>console</format>
    </formats>
</coverage>
```

Thresholds default to 70%. Raise or lower them via the `munit.coverage.*`
properties rather than editing the plugin block.

### Checking Logs

- **Pipeline console output:** Click on the build number → **Console Output**
- **Stage-level logs:** Click on any stage in the **Stage View** for details
- **Jenkins system log:** **Manage Jenkins → System Log**

---

## Quick-Start Checklist

- [ ] Jenkins installed and running
- [ ] Required plugins installed — including **Config File Provider** (Section 3)
- [ ] `anypoint-connected-app` credential created (Section 4.2)
- [ ] Managed `settings.xml` created with ID `maven-settings` and server credentials mapped (Section 4.3)
- [ ] Build agent has Java, Maven, Git, and the `mule-builder` label (Section 5)
- [ ] `pom.xml` has Maven profiles for `dev`, `test`, `uat`, `prod` (Section 7)
- [ ] Managed `settings.xml` includes the `<properties>` block, not just `<servers>` (Section 4.3)
- [ ] `APP_BASE_URL_<ENV>` set for the environments you want smoke tested (Section 8)
- [ ] `Jenkinsfile` placed in repo root (no `.txt` extension)
- [ ] Pipeline job created pointing to your repo (Section 6)
- [ ] First build triggered to register parameters
- [ ] (Optional) GitHub webhook configured for automatic triggers
