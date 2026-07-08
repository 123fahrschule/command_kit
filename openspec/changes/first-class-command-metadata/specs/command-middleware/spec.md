# command-middleware Delta

## MODIFIED Requirements

### Requirement: Middleware context access
Middleware SHALL be able to read and update the runtime command context through public context APIs.

#### Scenario: Middleware stores resolved actor
- **WHEN** middleware resolves an actor from the command's metadata
- **THEN** it can store that actor in the runtime context for later middleware and `execute/2` handlers

#### Scenario: Middleware stores transaction state
- **WHEN** middleware opens a transaction or prepares transaction-related state
- **THEN** it can store runtime-only transaction state in the context without modifying the command

### Requirement: Idempotency middleware
The library SHALL provide idempotency middleware that reuses successful results for repeated commands with the same idempotency key. The key MUST be resolved through the metadata accessor API so that keys stored as additional metadata are found. The command fingerprint MUST be derived from the command module and declared params only — never from `command_id` or metadata — so a retried command built fresh from the same params fingerprints identically.

#### Scenario: First dispatch stores result
- **WHEN** a command with an idempotency key completes with a cacheable success result
- **THEN** the idempotency middleware stores that result using the command fingerprint and idempotency key

#### Scenario: Repeated dispatch returns cached result
- **WHEN** the same command fingerprint and idempotency key are dispatched again
- **THEN** the idempotency middleware returns the cached result without executing the handler

#### Scenario: Error result is not cached
- **WHEN** a command with an idempotency key returns an error
- **THEN** the idempotency middleware does not cache that result

#### Scenario: Key stored as additional metadata is found
- **WHEN** a caller sets the idempotency key via `put_metadata(:idempotency_key, value)`
- **THEN** the idempotency middleware resolves that key through `CommandKit.Metadata.get/2`

#### Scenario: Rebuilt command fingerprints identically
- **WHEN** two command instances are built from the same params with different `command_id`s and timestamps and carry the same idempotency key
- **THEN** both dispatches resolve to the same idempotency cache entry

### Requirement: Authorization middleware
The library SHALL provide authorization middleware that delegates authorization decisions to application-provided command authorization logic. Authorizer callbacks receive the command (with its metadata) and the runtime context; there is no separate metadata argument.

#### Scenario: Authorization succeeds
- **WHEN** authorization returns `:ok`
- **THEN** the pipeline continues

#### Scenario: Authorization fails
- **WHEN** authorization returns `{:error, reason}`
- **THEN** the pipeline halts with `{:error, reason}`

#### Scenario: Authorizer reads the actor
- **WHEN** an application authorizer needs the acting user
- **THEN** it reads `command.metadata.enacted_by` instead of a separate metadata argument
