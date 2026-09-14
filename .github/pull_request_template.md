## What changed

<!-- One or two sentences. Link the ticket. -->

## Why

<!-- The problem this solves, not a restatement of the diff. -->

## API contract

- [ ] `src/main/resources/api/api.raml` updated (or: no contract change)
- [ ] Breaking change for existing consumers? If yes, say who was told and how.
- [ ] Examples in `api/examples/` still match the types

## Checks

- [ ] `mvn clean test` passes locally
- [ ] New/changed flows have MUnit coverage
- [ ] End-to-end behaviour verified in `api-e2e-test-suite.xml` where it touches routing, status codes, or the error envelope
- [ ] No secret, key, token, or real hostname added to `properties/*.yaml` — secrets belong in `properties/<env>-secure.yaml`, encrypted
- [ ] All four `properties/<env>.yaml` files updated if a new property was introduced
- [ ] Payload logging (`logging.payloads`) still `"false"` outside dev

## Deployment notes

<!-- New properties to set in Runtime Manager, API Manager policy changes,
     ordering constraints with other services, rollback plan. "None" is a
     valid answer. -->
