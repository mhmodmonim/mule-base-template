# Mule API Base Template

> **Version:** 1.0.2 | **Mule Runtime:** 4.11.0 | **Java:** 17 | **Packaging:** `mule-application`

A MuleSoft Mule 4 starter template that provides a production-ready foundation for building APIs on the Anypoint Platform. It includes a global error handler, secure property configuration, APIkit routing, environment-based YAML configs, and a Jenkins CI/CD pipeline — all pre-wired so new projects can go from zero to deployed in minutes.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Getting Started](#getting-started)
   - [Clone the Repository](#1-clone-the-repository)
   - [Import into Anypoint Studio](#2-import-into-anypoint-studio)
   - [Configure Maven Settings](#3-configure-maven-settings)
5. [Configuration](#configuration)
   - [Environment Property Files](#environment-property-files)
   - [Secure Properties](#secure-properties)
   - [Global Configurations](#global-configurations)
6. [Global Error Handler](#global-error-handler)
7. [Health Check Endpoint](#health-check-endpoint)
8. [Building the Project](#building-the-project)
9. [Running Locally](#running-locally)
10. [Running MUnit Tests](#running-munit-tests)
11. [Deployment](#deployment)
    - [Deploy via Maven CLI](#deploy-via-maven-cli)
    - [Deploy via Anypoint Studio](#deploy-via-anypoint-studio)
    - [Deploy via Jenkins CI/CD](#deploy-via-jenkins-cicd)
12. [Publishing to Anypoint Exchange](#publishing-to-anypoint-exchange)
13. [Logging](#logging)
14. [Troubleshooting](#troubleshooting)
15. [Contributing](#contributing)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   API Consumer                      │
└──────────────────────┬──────────────────────────────┘
                       │  HTTPS
┌──────────────────────▼──────────────────────────────┐
│               Anypoint API Gateway                  │
│            (Policies / Client Enforcement)           │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│            mule-api-base-template                   │
│  ┌───────────────────────────────────────────────┐  │
│  │  main.xml  (HTTP Listener + APIkit Router)    │  │
│  ├───────────────────────────────────────────────┤  │
│  │  global.xml (Secure Properties Config)        │  │
│  ├───────────────────────────────────────────────┤  │
│  │  global-error-handler.xml                     │  │
│  ├───────────────────────────────────────────────┤  │
│  │  implementation/health-check.xml              │  │
│  ├───────────────────────────────────────────────┤  │
│  │  subflows/ (your business logic goes here)    │  │
│  └───────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────┐  │
│  │  {env}.yaml  — per-environment properties     │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| **Java JDK** | 17 | Required by Mule Runtime 4.11 |
| **Apache Maven** | 3.8.x+ | Used to build, test, and deploy |
| **Anypoint Studio** | 7.x | IDE for MuleSoft development |
| **Mule Runtime** | 4.11.0 | Embedded in Studio or standalone |
| **Anypoint Platform Account** | — | For CloudHub deployment and Exchange access |
| **Git** | 2.x+ | Source control |

---

## Project Structure

```
mule-api-base-template/
├── pom.xml                          # Maven project descriptor & deployment config
├── mule-artifact.json               # Mule artifact metadata (min runtime, Java version, secure props)
├── settings.xml                     # Maven settings template (Exchange & repository credentials)
├── Jenkinsfile                      # Declarative Jenkins CI/CD pipeline
├── Jenkins-README.md                # Detailed Jenkins setup guide
│
├── src/
│   ├── main/
│   │   ├── mule/
│   │   │   ├── main.xml             # Primary flow: HTTP Listener → APIkit Router
│   │   │   ├── global.xml           # Secure properties configuration
│   │   │   ├── global-error-handler.xml  # Centralized error handling
│   │   │   ├── implementation/
│   │   │   │   └── health-check.xml # GET /health-check endpoint
│   │   │   └── subflows/            # Place your business logic subflows here
│   │   │
│   │   ├── resources/
│   │   │   ├── dev.yaml             # Dev environment properties
│   │   │   ├── test.yaml            # Test environment properties
│   │   │   ├── uat.yaml             # UAT environment properties
│   │   │   ├── prod.yaml            # Production environment properties
│   │   │   ├── log4j2.xml           # Logging configuration
│   │   │   └── api/                 # Place your RAML/OAS API specification here
│   │   │
│   │   └── java/                    # Custom Java classes (if needed)
│   │
│   └── test/
│       ├── munit/                   # MUnit test suites
│       ├── resources/
│       │   └── log4j2-test.xml      # Test-specific logging config
│       └── java/                    # Test Java classes
│
└── target/                          # Build output (generated — do not commit)
```

---

## Getting Started

### 1. Clone the Repository

```bash
git clone <your-repo-url> mule-api-base-template
cd mule-api-base-template
```

### 2. Import into Anypoint Studio

1. Open **Anypoint Studio**.
2. Go to **File → Import → Anypoint Studio → Anypoint Studio project from File System**.
3. Browse to the cloned directory and click **Finish**.
4. Studio will resolve Maven dependencies automatically.

### 3. Configure Maven Settings

Copy the included `settings.xml` template to your Maven home, or merge it with your existing settings:

```bash
# Option A — use as-is (backs up existing settings first)
cp ~/.m2/settings.xml ~/.m2/settings.xml.bak
cp settings.xml ~/.m2/settings.xml

# Option B — on Windows (PowerShell)
Copy-Item "$env:USERPROFILE\.m2\settings.xml" "$env:USERPROFILE\.m2\settings.xml.bak"
Copy-Item settings.xml "$env:USERPROFILE\.m2\settings.xml"
```

Then edit `~/.m2/settings.xml` and replace the placeholders:

| Placeholder | Description |
|---|---|
| `--username--` | Anypoint Platform username |
| `--password--` | Anypoint Platform password |
| `--encrypt-key--` | Encryption key for secure properties |
| `--client-id--` | Anypoint Connected App Client ID |
| `--client-secret--` | Anypoint Connected App Client Secret |

> **Security Note:** Never commit credentials to source control. Use environment variables or a secrets manager in CI/CD pipelines.

---

## Configuration

### Environment Property Files

The project uses per-environment YAML files under `src/main/resources/`:

| File | Environment | Purpose |
|---|---|---|
| `dev.yaml` | Development | Local dev & Sandbox |
| `test.yaml` | Test | Integration testing |
| `uat.yaml` | UAT | User acceptance testing |
| `prod.yaml` | Production | Live production |

Each file contains:

```yaml
http:
  port: "8081"                       # HTTP listener port

database:
  uhub:
    host: "localhost"                # Database host
    port: "3306"                     # Database port
    user: "root"                     # Database user
    password: "![encrypted_value]"   # Encrypted password (secure property)
```

The active environment is selected at runtime via the `env` system property (e.g., `-Denv=dev`).

### Secure Properties

Sensitive values (passwords, keys, secrets) are encrypted using the **Mule Secure Configuration Properties Module** (v1.3.0).

**How it works:**

1. Properties wrapped in `![...]` in YAML files are encrypted values.
2. The `global.xml` configures `secure-properties:config` to decrypt using the `enc.key` system property.
3. At runtime, pass the decryption key: `-Denc.key=your-secret-key`

**To encrypt a new value:**

```bash
# Using the Mule Secure Properties Tool JAR
java -cp secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool \
  string encrypt AES CBC <your-encryption-key> <value-to-encrypt>
```

The following properties are marked as secure in `mule-artifact.json` and will never appear in logs or the Runtime Manager UI:

- `enc.key`
- `anypoint.platform.client_id`
- `anypoint.platform.client_secret`

### Global Configurations

**`global.xml`** — Loads the environment-specific YAML and decrypts secure properties:

```xml
<secure-properties:config name="Secure_Properties_Config"
    file="${env}.yaml" key="${enc.key}" />
```

---

## Global Error Handler

The `global-error-handler.xml` provides centralized error handling that maps Mule errors to standard HTTP status codes:

| Error Type | HTTP Status | Message |
|---|---|---|
| `APIKIT:BAD_REQUEST` | 400 | Bad request |
| `APIKIT:NOT_FOUND` | 404 | Not found |
| `APIKIT:METHOD_NOT_ALLOWED` | 405 | Method Not Allowed |
| `APIKIT:NOT_ACCEPTABLE` | 406 | Not Acceptable |
| `APIKIT:UNSUPPORTED_MEDIA_TYPE` | 415 | Unsupported media type |
| `HTTP:BAD_REQUEST` | 400 | (passthrough from upstream) |
| `HTTP:CLIENT_SECURITY` | 401 | (passthrough from upstream) |
| `HTTP:SECURITY` | 401 | Unauthorized |
| `HTTP:FORBIDDEN` | 403 | Access forbidden |
| `HTTP:NOT_FOUND` | 404 | Not found |
| `HTTP:METHOD_NOT_ALLOWED` | 405 | Method not allowed |
| `HTTP:NOT_ACCEPTABLE` | 406 | Not acceptable |
| `HTTP:INTERNAL_SERVER_ERROR` | 500 | Upstream service error |
| `HTTP:CONNECTIVITY` | 503 | Service unavailable |
| `HTTP:RETRY_EXHAUSTED` | 503 | Service unavailable |
| `HTTP:TIMEOUT` | 504 | Gateway timeout |
| `HTTP:PARSING` | 400 | Bad request |
| *(catch-all)* | 500 | Internal Server Error |

All errors are routed through `global-prepare-error-response-sub-flow` to produce a consistent JSON error payload.

---

## Health Check Endpoint

A built-in health check is available at:

```
GET http://localhost:8081/health-check
```

**Response:**

```json
{
  "status": "UP",
  "message": "mule-api-base-template is alive and kicking"
}
```

Use this endpoint for load balancer health probes and uptime monitors.

---

## Building the Project

```bash
# Clean build (skip tests)
mvn clean package -DskipMunitTests

# Clean build (with tests)
mvn clean package

# Build with a specific environment profile
mvn clean package -Pdev
```

The built artifact is generated at `target/mule-api-base-template-1.0.2-mule-application.jar`.

---

## Running Locally

### Option A: Anypoint Studio

1. Right-click the project → **Run As → Mule Application**.
2. In the **Run Configuration**, add VM arguments:
   ```
   -Denv=dev -Denc.key=your-secret-key
   ```
3. The application starts on `http://localhost:8081`.

### Option B: Standalone Mule Runtime

```bash
# Build the project first
mvn clean package -DskipMunitTests

# Deploy to standalone runtime
cp target/mule-api-base-template-1.0.2-mule-application.jar $MULE_HOME/apps/

# Or run with Maven
mvn clean package -DskipMunitTests -Denv=dev -Denc.key=your-secret-key
```

### Option C: Maven with Mule Maven Plugin

```bash
mvn clean package mule:run -Denv=dev -Denc.key=your-secret-key
```

### Verify the Application

```bash
curl http://localhost:8081/health-check
# Expected: {"status":"UP","message":"mule-api-base-template is alive and kicking"}
```

---

## Running MUnit Tests

```bash
# Run all MUnit tests
mvn test

# Run tests with coverage report
mvn test -Dmunit.coverage.enabled=true

# Run a specific test suite
mvn test -Dmunit.test=health-check-test-suite.xml
```

Test reports are generated at:
- **Surefire reports:** `target/surefire-reports/`
- **MUnit coverage:** `target/site/munit/coverage/summary.html`

---

## Deployment

### Deploy via Maven CLI

Deployment uses the **Mule Maven Plugin** with the `cloudhub2Deployment` configuration. The `dev` profile in `pom.xml` targets:
- **Environment:** Sandbox
- **Target:** Cloudhub-US-East-2
- **Replicas:** 1
- **vCores:** 0.1

```bash
# Deploy to dev (Sandbox)
mvn clean deploy -Pdev -DmuleDeploy \
  -Dusername=<anypoint-username> \
  -Dpassword=<anypoint-password> \
  -Denv=dev \
  -Denc.key=<encryption-key> \
  -Dapi.id=<api-manager-instance-id> \
  -Danypoint.platform.client_id=<client-id> \
  -Danypoint.platform.client_secret=<client-secret>
```

**Key deployment parameters:**

| Parameter | Description |
|---|---|
| `-Pdev` | Activates the `dev` Maven profile |
| `-DmuleDeploy` | Triggers CloudHub deployment |
| `-Dusername` | Anypoint Platform username |
| `-Dpassword` | Anypoint Platform password |
| `-Denv` | Target environment (dev/test/uat/prod) |
| `-Denc.key` | Secure properties decryption key |
| `-Dapi.id` | API Manager instance ID for autodiscovery |
| `-Danypoint.platform.client_id` | Environment Client ID (for API Analytics) |
| `-Danypoint.platform.client_secret` | Environment Client Secret |

### Deploy via Anypoint Studio

1. Right-click the project → **Anypoint Platform → Deploy to CloudHub**.
2. Select the target environment and runtime version.
3. Configure application properties in the **Properties** tab.
4. Click **Deploy Application**.

### Deploy via Jenkins CI/CD

The project includes a fully configured `Jenkinsfile` with a multi-stage pipeline:

```
Build & Unit Test → MUnit Tests → Deploy to Dev → Deploy to Staging → Approval → Deploy to Production
```

**Pipeline features:**
- Parameterized builds (environment selection, app name)
- Connected App credentials injection
- MUnit test reports and coverage HTML publishing
- Manual approval gate for production deployments
- Automatic retry on deployment failures
- Workspace cleanup

Refer to [Jenkins-README.md](Jenkins-README.md) for full Jenkins setup instructions including:
- Jenkins server installation
- Required plugins
- Credentials configuration
- Build agent setup
- Pipeline job creation

**Quick start — create a Pipeline job:**

1. In Jenkins, create a **New Item → Pipeline**.
2. Under **Pipeline**, select **Pipeline script from SCM**.
3. Set **SCM** to Git and provide the repository URL.
4. Set **Script Path** to `Jenkinsfile`.
5. Save and click **Build with Parameters**.

---

## Publishing to Anypoint Exchange

The `pom.xml` includes `distributionManagement` configured for Anypoint Exchange:

```bash
# Publish the template to Exchange
mvn clean deploy -DskipMunitTests \
  -s settings.xml
```

Ensure your `settings.xml` has valid credentials for the `Repository` server ID.

---

## Logging

Logging is configured via `src/main/resources/log4j2.xml`:

- **Log file:** `${MULE_HOME}/logs/mule-api-base-template.log`
- **Pattern:** `%-5p %d [%t] [processor: %X{processorPath}; event: %X{correlationId}] %c: %m%n`
- **Rotation:** 10 MB per file, max 10 files
- **Default level:** INFO
- **HTTP wire logging:** WARN (set to DEBUG for request/response tracing)

### Adjusting Log Levels

Edit `log4j2.xml` to change levels:

```xml
<!-- Enable HTTP wire-level debug logging -->
<AsyncLogger name="org.mule.service.http.impl.service.HttpMessageLogger" level="DEBUG"/>

<!-- Enable detailed Mule runtime logging -->
<AsyncLogger name="org.mule.runtime.core" level="DEBUG"/>
```

For test execution, a separate config is used: `src/test/resources/log4j2-test.xml`.

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|---|---|---|
| `Could not resolve dependencies` | Missing Exchange credentials | Configure `settings.xml` with valid Anypoint credentials |
| `Encryption key not set` | Missing `-Denc.key` | Pass `-Denc.key=<key>` as a VM argument or system property |
| `Port 8081 already in use` | Another app on the same port | Stop the conflicting app or change `http.port` in the YAML |
| `APIKIT:NOT_FOUND` on all routes | Missing API specification | Place your RAML/OAS spec in `src/main/resources/api/` and update `main.xml` |
| `java.lang.UnsupportedClassVersionError` | Wrong Java version | Ensure JDK 17 is installed and configured |
| `401 Unauthorized` on deploy | Invalid credentials | Verify Anypoint username/password or Connected App credentials |
| `BUILD FAILURE - mule-maven-plugin` | Plugin version mismatch | Ensure `mule.maven.plugin.version` is `4.7.0` in `pom.xml` |

### Useful Maven Commands

```bash
# Check effective POM (resolved properties and profiles)
mvn help:effective-pom -Pdev

# Check dependency tree
mvn dependency:tree

# Verify project structure without building
mvn validate

# Run in debug mode for verbose output
mvn clean package -X
```

---

## Contributing

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Place your API specification (RAML/OAS) in `src/main/resources/api/`.
3. Implement your flows in `src/main/mule/implementation/`.
4. Add reusable subflows to `src/main/mule/subflows/`.
5. Write MUnit tests in `src/test/munit/`.
6. Update environment YAML files with any new properties.
7. Run tests locally: `mvn clean test`
8. Open a pull request targeting `main`.

---

## Dependencies

| Module | Version | Purpose |
|---|---|---|
| `mule-http-connector` | 1.11.1 | HTTP Listener and Request |
| `mule-sockets-connector` | 1.2.7 | Low-level socket support |
| `mule-secure-configuration-property-module` | 1.3.0 | Encrypted property decryption |
| `mule-apikit-module` | 1.11.16 | APIkit Router, auto-generated flows from RAML/OAS |

---

## License

This project is a MuleSoft template. Refer to your organization's licensing policy.
