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
| Username       | `<your Connected App Client ID>`           |
| Password       | `<your Connected App Client Secret>`       |
| ID             | `anypoint-connected-app`                   |
| Description    | Anypoint Platform Connected App Credentials |

4. Click **Create**.

> **Important:** The credential ID **must** match `anypoint-connected-app` — this is the ID referenced in the Jenkinsfile.

### 4.3 Configure Managed Maven `settings.xml` (Config File Provider)

The Jenkinsfile uses the **Config File Provider** plugin to inject a managed `settings.xml` into every Maven invocation. This avoids placing credentials on the agent's filesystem.

1. Go to **Manage Jenkins → Managed files → Add a new Config**.
2. Select **Maven settings.xml**, click **Submit**.
3. Set:

| Field  | Value              |
| ------ | ------------------ |
| ID     | `maven-settings`   |
| Name   | MuleSoft Maven Settings |

4. Paste the following content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings>
    <servers>
        <server>
            <id>anypoint-exchange-v3</id>
            <!-- credentials injected by Config File Provider -->
        </server>
        <server>
            <id>mulesoft-releases</id>
            <!-- credentials injected by Config File Provider -->
        </server>
    </servers>

    <profiles>
        <profile>
            <id>mulesoft</id>
            <repositories>
                <repository>
                    <id>mulesoft-releases</id>
                    <name>MuleSoft Releases</name>
                    <url>https://repository.mulesoft.org/releases/</url>
                </repository>
                <repository>
                    <id>anypoint-exchange-v3</id>
                    <name>Anypoint Exchange V3</name>
                    <url>https://maven.anypoint.mulesoft.com/api/v3/maven</url>
                </repository>
            </repositories>
            <pluginRepositories>
                <pluginRepository>
                    <id>mulesoft-releases</id>
                    <name>MuleSoft Releases</name>
                    <url>https://repository.mulesoft.org/releases/</url>
                </pluginRepository>
            </pluginRepositories>
        </profile>
    </profiles>

    <activeProfiles>
        <activeProfile>mulesoft</activeProfile>
    </activeProfiles>
</settings>
```

5. Under **Server Credentials**, map each `<server>` ID to the Jenkins credential:

| Server ID               | Credentials                |
| ----------------------- | -------------------------- |
| `anypoint-exchange-v3`  | `anypoint-connected-app`   |
| `mulesoft-releases`     | `anypoint-connected-app`   |

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

Your MuleSoft project should look like this:

```
my-mule-app/
├── Jenkinsfile                  ← Pipeline definition (this file)
├── pom.xml                      ← Maven POM with CloudHub deploy plugin config
├── src/
│   ├── main/
│   │   ├── mule/               ← Mule XML flows
│   │   └── resources/          ← Properties files
│   └── test/
│       └── munit/              ← MUnit test suites
└── mule-artifact.json
```

### Key `pom.xml` Configuration

The Jenkinsfile activates a **Maven profile** per environment (`-P dev`, `-P staging`, `-P prod`). Your `pom.xml` must define these profiles with the corresponding deployment configuration.

#### Deployment Plugin (shared configuration)

```xml
<plugin>
    <groupId>org.mule.tools.maven</groupId>
    <artifactId>mule-maven-plugin</artifactId>
    <version>4.2.1</version>
    <extensions>true</extensions>
</plugin>
```

#### Environment Profiles

Add a `<profiles>` section with one profile per environment. The Jenkinsfile invokes `mvn deploy -P<env>`, so the profile `<id>` must match:

```xml
<profiles>
    <profile>
			<id>dev</id>
			<build>
				<plugins>
					<plugin>
						<groupId>org.apache.maven.plugins</groupId>
						<artifactId>maven-clean-plugin</artifactId>
						<version>3.2.0</version>
					</plugin>
					<plugin>
						<groupId>org.mule.tools.maven</groupId>
						<artifactId>mule-maven-plugin</artifactId>
						<version>${mule.maven.plugin.version}</version>
						<extensions>true</extensions>
						<configuration>
							<cloudhub2Deployment>
								<applicationName>${project.artifactId}</applicationName>
								<environment>Sandbox</environment>
								<target>Cloudhub-US-East-2</target>
								<replicas>1</replicas>
								<vCores>0.1</vCores>
								<properties>
									<env>dev</env>
									<api.id>${api.id}</api.id>
									<enc.key>${enc.key}</enc.key>
									<anypoint.platform.client_id>${anypoint.platform.client_id}</anypoint.platform.client_id>
									<anypoint.platform.client_secret>${anypoint.platform.client_secret}</anypoint.platform.client_secret>
								</properties>
							</cloudhub2Deployment>
						</configuration>
					</plugin>
				</plugins>
			</build>
		</profile>
    <profile>
        <!-- <id>staging</id> -->
    </profile>
    <profile>
        <!-- <id>prod</id> -->
    </profile>
</profiles>
```

> **Note:** The `connectedApp.clientId` and `connectedApp.clientSecret` properties are resolved from the managed `settings.xml` server credentials (see [Section 4.3](#43-configure-managed-maven-settingsxml-config-file-provider)).

---

## 8. Jenkinsfile Walkthrough

### Pipeline Flow

```
┌─────────────────────┐
│  Build & Unit Test   │  mvn clean package -s $MAVEN_SETTINGS -DskipMunitTests
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│    MUnit Tests       │  mvn test -s $MAVEN_SETTINGS → JUnit + Coverage HTML
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│   Deploy to Dev      │  Always runs (for any env choice)
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│  Deploy to Staging   │  Runs if env = staging or prod
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│  Approval Gate       │  Manual approval (prod only) — 24h timeout
└─────────┬───────────┘
          │
┌─────────▼───────────┐
│ Deploy to Production │  Runs if env = prod AND approved
└─────────────────────┘
```

### Key Behaviors

| Feature                   | Details                                                    |
| ------------------------- | ---------------------------------------------------------- |
| **Maven settings**        | Injected per-step via `configFileProvider` (`maven-settings`); auto-cleaned after each block |
| **Credentials injection** | `ANYPOINT_CREDS_USR` / `ANYPOINT_CREDS_PSW` auto-created from `credentials()` |
| **Maven profiles**        | Deploy uses `-P<env>` to activate the matching pom.xml profile (`dev`, `staging`, `prod`) |
| **Retry on deploy**       | Each deploy retries up to 2 times on failure               |
| **Concurrent builds**     | Disabled — only one build runs at a time                   |
| **Timeout**               | 60 min total pipeline, 24 hours for prod approval          |
| **Artifacts**             | JAR archived with fingerprint; `allowEmptyArchive: true` prevents build failure if no JAR |
| **Test reports**          | JUnit XML + MUnit coverage HTML; `allowMissing: true` prevents build failure if report dir is absent |

---

## 9. Running the Pipeline

### First Run

1. Open the pipeline job in Jenkins.
2. Click **Build with Parameters**.
3. Select:
   - **ENVIRONMENT**: `dev` (start with dev for first test)
   - **APP_NAME**: `my-mule-app` (or your app name)
4. Click **Build**.

> **Note:** The first run will also register the parameters in Jenkins. If you don't see **Build with Parameters**, click **Build Now** once — it will fail but register the parameters for subsequent runs.

### Deploying Through Environments

| Scenario         | ENVIRONMENT param | What happens                                    |
| ---------------- | ----------------- | ----------------------------------------------- |
| Dev only         | `dev`             | Build → Test → Deploy to Dev                    |
| Up to Staging    | `staging`         | Build → Test → Deploy to Dev → Deploy to Staging |
| Full Production  | `prod`            | Build → Test → Dev → Staging → Approval → Prod  |

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
| Deploy succeeds but wrong env config | Maven profile mismatch | Ensure `pom.xml` has `<profile>` entries with `<id>dev</id>`, `<id>staging</id>`, `<id>prod</id>` matching the `-P<env>` flag |

### Enabling MUnit Coverage in `pom.xml`

```xml
<plugin>
    <groupId>com.mulesoft.munit.tools</groupId>
    <artifactId>munit-maven-plugin</artifactId>
    <version>3.2.1</version>
    <executions>
        <execution>
            <id>test</id>
            <phase>test</phase>
            <goals>
                <goal>test</goal>
                <goal>coverage-report</goal>
            </goals>
        </execution>
    </executions>
    <configuration>
        <coverage>
            <runCoverage>true</runCoverage>
            <formats>
                <format>html</format>
            </formats>
        </coverage>
    </configuration>
</plugin>
```

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
- [ ] `pom.xml` has Maven profiles for `dev`, `staging`, `prod` with deployment config (Section 7)
- [ ] `Jenkinsfile` placed in repo root (no `.txt` extension)
- [ ] Pipeline job created pointing to your repo (Section 6)
- [ ] First build triggered to register parameters
- [ ] (Optional) GitHub webhook configured for automatic triggers
