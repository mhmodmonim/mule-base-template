# Mule API Base Template

> **Mule Runtime:** 4.11.0 · **Java:** 17 · **Packaging:** `mule-application` · **MUnit:** 3.7.4

A Mule 4 starter template for new API projects. It is not a skeleton — it is a
working, tested API: clone it, run `mvn test`, and 18 MUnit tests pass against a
real HTTP listener.

**What you get out of the box**

| | |
| --- | --- |
| **RAML 1.0 contract** | `/health-check` plus a reference `/example` resource, with types, traits and examples |
| **APIkit routing** | Wired listener → router → implementation flows, with request validation on |
| **Global error handler** | ~30 error types mapped to correct status codes and one JSON envelope that matches the RAML |
| **Structured JSON logging** | Correlation-id propagation end to end, payload logging gated per environment |
| **Split configuration** | Plain config and secrets in separate files, per environment, for four environments |
| **MUnit suite** | Flow-level *and* end-to-end tests through the real listener, with coverage reporting |
| **Jenkins pipeline** | Build once, promote dev → test → uat → prod, smoke test after each deploy |
| **Build metadata** | Maven stamps version and build time into the app; `/health-check` reports them |

---

## Table of Contents

1. [Quick start](#quick-start)
2. [Architecture](#architecture)
3. [Project structure](#project-structure)
4. [Configuration](#configuration)
5. [The API contract](#the-api-contract)
6. [Error handling](#error-handling)
7. [Logging](#logging)
8. [Testing](#testing)
9. [Deployment](#deployment)
10. [Making this your project](#making-this-your-project)
11. [Conventions](#conventions)
12. [Troubleshooting](#troubleshooting)

---

## Quick start

```bash
git clone <this-repo> my-new-api
cd my-new-api

# Build and run the full test suite. No credentials needed.
mvn clean test
```

Expected output:

```
 >> health-check-test-suite.xml        Tests: 2, Errors: 0, Failures: 0
 >> example-test-suite.xml             Tests: 6, Errors: 0, Failures: 0
 >> global-error-handler-test-suite.xml Tests: 3, Errors: 0, Failures: 0
 >> api-e2e-test-suite.xml             Tests: 7, Errors: 0, Failures: 0
 > Tests: 18   Errors: 0   Failures: 0
```

To run it locally in Anypoint Studio: **Run As → Mule Application**, then add
these VM arguments in the run configuration:

```
-Denv=dev -Denc.key=localDevOnlyKey0
```

Both have safe fallbacks in `global.xml`, so it will start without them — but
set them explicitly so local runs match deployed ones.

Then:

```bash
curl http://localhost:8081/api/health-check
# {"status":"UP","application":"mule-api-base-template","version":"1.0.2",...}
```

The APIkit console is at <http://localhost:8081/api/console/> in `dev`.

**Prerequisites:** JDK 17 (the build enforces it), Maven 3.8+, and — only for
deploying — an Anypoint connected app. Building and testing need no Anypoint
credentials at all.

---

## Architecture

```
                        HTTP(S)
  API consumer ───────────────────────► HTTP_Listener_config   (global.xml)
                                          basePath /api
                                                │
                                        ┌───────▼────────┐
                                        │   main-flow    │      (main.xml)
                                        │                │
                                        │ 1 correlationId│  ← from x-correlation-id
                                        │ 2 request log  │      or generated
                                        │ 3 APIkit router│  ← validates against RAML
                                        │ 4 response log │
                                        └───────┬────────┘
                                                │  resolves flow by name
                       ┌────────────────────────┼────────────────────────┐
                       ▼                        ▼                        ▼
        get:\health-check:Router     get:\example:Router      post:\example:...:Router
                       │                        │                        │
                       └────────────────────────┼────────────────────────┘
                                                │  raise-error APP:*
                                                ▼
                                     global-error-handler          (global-error-handler.xml)
                                                │
                                     build-error-response-sub-flow
                                       ├─ ERROR log (JSON)
                                       └─ error envelope (JSON)
                                                │
                                                ▼
                                     <http:error-response>
                                       status  ← vars.httpStatus
                                       headers ← vars.outboundHeaders
                                                 + x-correlation-id
```

The contract between the pieces is three variables:

| Variable | Set by | Read by |
| --- | --- | --- |
| `vars.httpStatus` | implementation flows and every error handler block | the listener's `<http:response>` / `<http:error-response>` |
| `vars.outboundHeaders` | APIkit router, error handler | the listener's response builders |
| `vars.correlationId` | `main-flow`, from the inbound header or the runtime id | logs, error envelope, response header, outbound requests |

Nothing sets the HTTP status on the message itself. Keeping it in
`vars.httpStatus` is what lets any flow — including one nested three levels
deep — decide the response code.

---

## Project structure

```
.
├── Jenkinsfile                      Jenkins promote pipeline      (Jenkins-README.md)
├── azure-pipelines.yml              Azure DevOps promote pipeline (Azure-DevOps-README.md)
├── .azure-pipelines/templates/      Deploy stage + Maven setup templates
├── .github/
│   ├── workflows/ci.yml             Build + MUnit on PRs and main (GitHub-Actions-README.md)
│   ├── workflows/deploy.yml         Manual promote pipeline
│   ├── workflows/_deploy-environment.yml   Reusable deploy + smoke test
│   ├── dependabot.yml               Keeps action versions current
│   └── pull_request_template.md
├── .ci/                             Shared by GitHub Actions and Azure DevOps
│   ├── maven-settings.xml           Credentials from env vars; no secrets
│   └── deploy.sh · smoke-test.sh · require-env.sh · munit-summary.sh
├── pom.xml                          Profiles: dev · test · uat · prod
├── mule-artifact.json               Runtime, Java version, secureProperties
├── settings-template.xml            Copy to ~/.m2/settings.xml and fill in
├── CODEOWNERS                       Review ownership (edit the team names)
├── .editorconfig / .gitattributes   Tab-indented XML, LF endings
└── src/
    ├── main/
    │   ├── build-info/
    │   │   └── build-info.properties     Maven-filtered (@...@ delimiters)
    │   ├── mule/
    │   │   ├── global.xml                Property loading, listener, requester
    │   │   ├── main.xml                  APIkit config, main-flow, console flow
    │   │   ├── global-error-handler.xml  Error mapping + envelope
    │   │   ├── common/
    │   │   │   └── logging.xml           Structured logging sub-flows
    │   │   └── implementation/
    │   │       ├── health-check.xml
    │   │       └── example.xml           Reference implementation — delete it
    │   └── resources/
    │       ├── api/
    │       │   ├── api.raml
    │       │   ├── dataTypes/            Library + traits
    │       │   └── examples/             Example payloads referenced by the RAML
    │       ├── properties/
    │       │   ├── dev.yaml   dev-secure.yaml
    │       │   ├── test.yaml  test-secure.yaml
    │       │   ├── uat.yaml   uat-secure.yaml
    │       │   └── prod.yaml  prod-secure.yaml
    │       └── log4j2.xml
    └── test/
        ├── munit/
        │   ├── health-check-test-suite.xml
        │   ├── example-test-suite.xml
        │   ├── global-error-handler-test-suite.xml
        │   └── api-e2e-test-suite.xml     End-to-end through the listener
        └── resources/log4j2-test.xml
```

---

## Configuration

### Two files per environment

| File | Loaded by | Contains | Needs `enc.key`? |
| --- | --- | --- | --- |
| `properties/<env>.yaml` | `<configuration-properties>` | hosts, ports, timeouts, feature flags | no |
| `properties/<env>-secure.yaml` | `<secure-properties:config>` | passwords, client secrets, keystore passwords | yes |

Splitting them keeps the encryption key's blast radius small, lets anyone read
the configuration without it, and means rotating a key touches one small file
per environment.

`env` selects the pair. `global.xml` declares defaults for local development:

```xml
<global-property name="env" value="dev"/>
<global-property name="enc.key" value="localDevOnlyKey0"/>
```

A system property always beats a `global-property`, so `-Denv=uat` or a
CloudHub application property wins. Never put a real key in `global.xml`.

### YAML values must be quoted strings

Mule's YAML property provider accepts strings only. This deploys:

```yaml
apikit:
  console:
    enabled: "true"
```

This fails at deployment with *"YAML configuration properties only supports
string values"*:

```yaml
apikit:
  console:
    enabled: true      # ← unquoted boolean
```

Numbers included. Every value in every `properties/*.yaml` is quoted for this
reason.

### What differs between environments

| Property | dev | test | uat | prod |
| --- | --- | --- | --- | --- |
| `apikit.console.enabled` | `"true"` | `"true"` | `"false"` | `"false"` |
| `logging.payloads` | `"true"` | `"false"` | `"false"` | `"false"` |
| `logging.level` | `DEBUG` | `INFO` | `INFO` | `WARN` |
| `backend.example.protocol` | `HTTP` | `HTTPS` | `HTTPS` | `HTTPS` |
| replicas / vCores (pom) | 1 / 0.1 | 1 / 0.1 | 2 / 0.2 | 2 / 0.5 |

> `logging.payloads: "true"` writes full request and response bodies to the
> log. That is fine in dev and a data-protection incident anywhere else.

### Encrypting a secret

```bash
java -cp secure-properties-tool.jar com.mulesoft.tools.SecurePropertiesTool \
     string encrypt AES CBC <enc.key> <plaintext>
```

Paste the result into the `-secure.yaml` file wrapped in `![...]`:

```yaml
backend:
  example:
    auth:
      clientSecret: "![kd8s7f6g5h4j3k2l1==]"
```

Values listed under `secureProperties` in `mule-artifact.json` are additionally
hidden from Runtime Manager's UI.

### Adding a property

Add it to **all four** `<env>.yaml` files (or all four `-secure.yaml` files).
A property that exists in only one environment fails deployment everywhere else
with `Couldn't find configuration property value for key ${...}`.

---

## The API contract

`src/main/resources/api/api.raml` is the source of truth. APIkit validates every
inbound request against it before your implementation flow runs — so query
parameter types, required fields, string patterns and payload schemas are
enforced for free, and produce a 400 with a per-field description.

```
api/
├── api.raml                        resources, methods, responses
├── dataTypes/
│   ├── library.raml                HealthStatus, Example, ErrorResponse, …
│   └── trait-correlated.raml       x-correlation-id in / out
└── examples/                       payloads referenced by the RAML
```

`ErrorResponse` in the library is the same shape the global error handler
produces. Keep them in sync — `global-error-handler-test-suite.xml` pins it.

### Adding a resource

1. Add it to `api.raml` (types in `dataTypes/library.raml`, sample payloads in `examples/`).
2. Add the implementation flow. The name must be exactly what APIkit derives:

   | RAML | Flow name |
   | --- | --- |
   | `GET /orders` | `get:\orders:Router` |
   | `POST /orders` with a JSON body | `post:\orders:application\json:Router` |
   | `GET /orders/{orderId}` | `get:\orders\(orderId):Router` |

   `Router` is the `<apikit:config>` name in `main.xml`. Note the **backslashes**
   and the **parentheses** around URI parameters. In Studio you can generate
   these: right-click the RAML → **Mule** → **Generate Flows**.
3. Add a test suite for it.

A route that exists in the RAML with no matching flow returns **501 Not
Implemented**, not 404 — that is APIkit telling you the name is wrong.

---

## Error handling

Every flow that owns a message source references the shared handler:

```xml
<error-handler ref="global-error-handler"/>
```

### The contract

Each `<on-error-propagate>` block sets at most three variables and delegates:

```xml
<on-error-propagate type="APIKIT:NOT_FOUND">
    <set-variable value="#[404]" variableName="httpStatus"/>
    <set-variable value="Not found" variableName="errorMessage"/>
    <set-variable value="The server has not found anything matching the request URI"
                  variableName="errorDescription"/>
    <flow-ref name="build-error-response-sub-flow"/>
</on-error-propagate>
```

`build-error-response-sub-flow` does the rest, in one place: the ERROR log line
and the JSON envelope.

```json
{
  "code": 404,
  "message": "Not found",
  "description": "Example ex-9999 does not exist",
  "dateTime": "2026-01-01T00:00:00Z",
  "correlationId": "0f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f"
}
```

### Mapping decisions worth knowing

- **Downstream 4xx are not mirrored.** A backend rejecting a request *we* built
  is our bug, not the caller's, so `HTTP:BAD_REQUEST`, `HTTP:NOT_FOUND`,
  `HTTP:UNAUTHORIZED` and `HTTP:FORBIDDEN` all surface as **502**. Change this
  if your consumers depend on pass-through semantics.
- **`TRANSFORMATION`, `EXPRESSION` and `ROUTING` are 500.** The detail is logged
  but not echoed to the client.
- **`APIKIT:BAD_REQUEST` becomes an array.** APIkit packs every schema violation
  into one newline-separated string; the handler splits it so `description` is a
  list of field errors.
- **Order matters.** Mule matches blocks in document order — most specific
  first. New blocks go above the `ANY` block.
- **`on-error-propagate`, never `on-error-continue`.** Continue would return
  HTTP 200 with an error body.

### Raising your own errors

```xml
<raise-error type="APP:RESOURCE_NOT_FOUND"
             description="#['Order ' ++ vars.orderId ++ ' does not exist']"/>
```

`APP:VALIDATION` (400) and `APP:RESOURCE_NOT_FOUND` (404) are wired up.
`APP:CONFLICT` (409) and `APP:UNPROCESSABLE` (422) are present but **commented
out**, because Mule only registers an `APP:*` type when some `<raise-error>`
actually uses it — a handler for an unused type fails the build with
`Could not find error 'APP:CONFLICT'`. Add the `raise-error` first, then
uncomment the block.

---

## Logging

`src/main/mule/common/logging.xml` provides three sub-flows that emit **one JSON
object per line**, so a log aggregator can parse them without a grok pattern:

| Sub-flow | Event | Called from |
| --- | --- | --- |
| `log-inbound-request-sub-flow` | `REQUEST_RECEIVED` | `main-flow`, before routing |
| `log-outbound-response-sub-flow` | `RESPONSE_SENT` | `main-flow`, after routing (includes `durationMs`) |
| `log-checkpoint-sub-flow` | `vars.checkpoint` | anywhere — set `vars.checkpoint` and optionally `vars.checkpointDetail` |

Plus `api.error` from the error handler, at ERROR level.

```json
{"event":"REQUEST_RECEIVED","correlationId":"0f1c…","application":"my-api",
 "environment":"dev","method":"POST","path":"/api/example","payload":"(omitted)"}
```

`payload` is `"(omitted)"` unless `logging.payloads` is `"true"`.

`log4j2.xml` attaches both a Console appender (what CloudHub and Anypoint
Monitoring collect) and a rolling File appender (hybrid/on-prem), with gzip
rotation and a 30-day retention. Override the root level at runtime with
`-Dlog.level=DEBUG`.

### Correlation IDs

`main-flow` takes the inbound `x-correlation-id` header, or falls back to
Mule's own `correlationId`. It then flows into every log line, the error
envelope, the response header, and — via `<http:default-headers>` on the
requester config — every outbound call.

---

## Testing

```bash
mvn clean test                                       # everything
mvn test -Dmunit.test=health-check-returns-UP        # one test, by <munit:test> name
mvn test -Dmunit.tags=smoke                          # by tag, if you add tags
mvn test -Dmunit.coverage.failBuild=true             # enforce the threshold
mvn package -DskipMunitTests                         # build without testing
```

> MUnit's skip switch is **`-DskipMunitTests`**. `-DskipTests` only affects
> Surefire and will not skip MUnit.

### Two kinds of suite

**Flow-level** (`health-check`, `example`, `global-error-handler`) call a flow
directly with `<flow-ref>`. Fast, precise, good for branch coverage.

**End-to-end** (`api-e2e-test-suite.xml`) makes real HTTP calls to the running
listener. These are the only tests that can catch a broken listener config, an
APIkit flow name that does not match the RAML, or an error handler returning the
wrong status code. Two things make them work:

```xml
<!-- A free port per run, so concurrent CI jobs cannot collide. -->
<munit:dynamic-port propertyName="http.listener.port"/>
```

```xml
<!-- MUnit disables message sources and initialises lazily. main-flow owns the
     listener; the APIkit target flows must be listed too, or the router
     resolves nothing and every call returns 501. -->
<munit:enable-flow-sources>
    <munit:enable-flow-source value="main-flow"/>
    <munit:enable-flow-source value="get:\health-check:Router"/>
    …
</munit:enable-flow-sources>
```

### Coverage

Reported on every build (console + `target/site/munit/coverage/summary.html`),
enforced only with `-Dmunit.coverage.failBuild=true`.

The untouched template sits at about **24%**. That is expected: `main.xml` and
the implementation flows are fully covered, but the global error handler
contains ~30 branches that only fire against real backend failures. As your own
flows become the bulk of the application that number rises — turn enforcement on
in CI once it does. Thresholds live in the `munit.coverage.*` properties in
`pom.xml`.

---

## Deployment

### Profiles

| Profile | `env` | Anypoint env | App name | Replicas | vCores |
| --- | --- | --- | --- | --- | --- |
| `dev` (default) | `dev` | Sandbox | `<artifactId>-dev` | 1 | 0.1 |
| `test` | `test` | Sandbox | `<artifactId>-test` | 1 | 0.1 |
| `uat` | `uat` | UAT | `<artifactId>-uat` | 2 | 0.2 |
| `prod` | `prod` | Production | `<artifactId>` | 2 | 0.5 |

Profiles override **Maven properties only**; there is a single
`<cloudhub2Deployment>` block in `<build>` that consumes them. Adding an
environment means adding a profile plus two YAML files — no plugin
configuration to duplicate.

### Deploying

```bash
cp settings-template.xml ~/.m2/settings.xml   # then fill in the placeholders
mvn deploy -Pdev  -DmuleDeploy
mvn deploy -Puat  -DmuleDeploy
mvn deploy -Pprod -DmuleDeploy
```

Authentication uses a **connected app** (client credentials), configured in
`settings.xml`, never in `pom.xml`. `settings.xml` is in `.gitignore` so a
filled-in copy cannot be committed.

### Publishing to Exchange

```bash
mvn deploy -DskipMunitTests    # without -DmuleDeploy
```

`<groupId>` must be your Anypoint organization id — Exchange rejects publishes
whose groupId does not match the target org.

### CI/CD

Three equivalent pipelines ship with the template. Each promotes the same
`artifactId:version` through dev → test → uat → approval → prod, with a
`/health-check` smoke test after each deploy. Use whichever your organisation
runs, and delete the others.

| Platform | Pipeline files | Setup guide |
| --- | --- | --- |
| Jenkins | `Jenkinsfile` | [`Jenkins-README.md`](./Jenkins-README.md) |
| GitHub Actions | `.github/workflows/ci.yml`, `deploy.yml`, `_deploy-environment.yml` | [`GitHub-Actions-README.md`](./GitHub-Actions-README.md) |
| Azure DevOps | `azure-pipelines.yml`, `.azure-pipelines/templates/` | [`Azure-DevOps-README.md`](./Azure-DevOps-README.md) |

GitHub Actions and Azure DevOps share `.ci/`: a `maven-settings.xml` that reads
every credential from environment variables (no secrets committed), plus the
deploy, smoke-test and configuration-check scripts.

### API Manager autodiscovery

Commented out in `global.xml`, because an app with an unset `api.id` will not
start. Once the API is registered in API Manager, uncomment the block, add the
`api-gateway` namespace to the `<mule>` element, and supply `api.id`.

### HTTPS

The default listener is plain HTTP, which is correct for CloudHub 2.0 — TLS is
terminated at the ingress. For hybrid, RTF or on-prem, `global.xml` has a
commented HTTPS listener config: drop the keystore into
`src/main/resources/tls/` (gitignored), fill in `http.tls.*`, and swap it in.

---

## Making this your project

1. **`pom.xml`** — set `groupId` to your Anypoint org id, plus `artifactId`,
   `version`, `name`, `description`.
2. **`log4j2.xml`** — replace `mule-api-base-template` in the two file paths.
3. **`properties/*.yaml`** — set `app.name`, real backend hosts, real secrets
   (encrypted).
4. **`api/api.raml`** — replace `/example` with your resources. Keep
   `/health-check`.
5. **Delete the reference implementation** —
   `src/main/mule/implementation/example.xml` and
   `src/test/munit/example-test-suite.xml`, plus the `/example` tests in
   `api-e2e-test-suite.xml`.
6. **`CODEOWNERS`** — replace the `@your-org/*` placeholders.
7. **CI/CD** — keep the pipeline for your platform and delete the others:
   `Jenkinsfile` ([guide](./Jenkins-README.md)), `.github/workflows/`
   ([guide](./GitHub-Actions-README.md)) or `azure-pipelines.yml` +
   `.azure-pipelines/` ([guide](./Azure-DevOps-README.md)). Keep `.ci/` for
   either of the last two.
8. **`settings-template.xml`** — copy to `~/.m2/settings.xml`, fill it in.

---

## Conventions

| | |
| --- | --- |
| **One file per concern** | `global.xml` configs · `main.xml` entry point · `implementation/<resource>.xml` per resource · one MUnit suite per implementation file |
| **No business logic in `main-flow`** | It routes; it does not decide |
| **No local error handlers** | Errors propagate to `global-error-handler`. Handle locally only when you can genuinely recover |
| **Status via `vars.httpStatus`** | Never on the message |
| **Business failures via `raise-error APP:*`** | Not by setting a status and returning normally |
| **Pinned versions** | No ranges, no `LATEST` — a build that resolves differently tomorrow is not reproducible |
| **Tab-indented XML** | Matches what Anypoint Studio writes; `.editorconfig` enforces it |
| **Property in one env = property in all four** | Otherwise deployment fails elsewhere |

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `YAML configuration properties only supports string values` | An unquoted boolean or number in a `properties/*.yaml` | Quote every value |
| `Couldn't find configuration property value for key ${x}` | Property missing from the active env file | Add it to all four env files |
| `Could not find error 'APP:X'` at build time | A handler block for an `APP:*` type nothing raises | Add the `<raise-error>` first, or comment the block out |
| HTTP **501** from a route that exists in the RAML | Implementation flow name does not match what APIkit derives | Check backslashes, the `(uriParam)` parentheses, and the `:Router` suffix |
| MUnit e2e tests get 501 | Target flows not listed in `<munit:enable-flow-sources>` | Lazy init left them uninstantiated — list them |
| MUnit e2e tests get *connection refused* | `main-flow` not in `<munit:enable-flow-sources>` | MUnit disables message sources by default |
| `read(payload, 'application/json')` fails in a test | The HTTP requester already parsed the JSON | Use `payload.field` directly |
| MUnit runs despite "skip tests" | Used `-DskipTests` | Use `-DskipMunitTests` |
| Cannot decrypt a `![...]` value | Wrong or missing `enc.key` | Pass `-Denc.key=...`; it must be the key the value was encrypted with |
| `401` resolving dependencies | Exchange credentials missing | Fill in `settings.xml`; for a connected app the username is the literal `~~~Client~~~` |
| Build fails on Java version | Wrong JDK | The enforcer requires JDK 17; point `JAVA_HOME` at it |
| No logs in the Studio console | — | Fixed here: `log4j2.xml` has both Console and File appenders |
