# Logging Runtime Ownership Design

## Summary

IRPlayer 2.0 currently exposes a process-wide logging API through three
unsynchronized mutable static properties:

- `IRPlayerImp.Logger.subsystem`;
- `IRPlayerImp.Logger.delegate`; and
- `IRPlayerImp.Logger.libraryLogger`.

The delegate is declared `nonisolated(unsafe)` and may be read, replaced, or
released concurrently with logging. The subsystem and logger may publish an
incoherent pair. FFmpeg and Metal runtime diagnostics additionally pass
through separate forwarding-only policy files and write directly to standard
output instead of the public logging boundary.

Replace these globals with one synchronized `IRPlayerLoggingSession`. Preserve
the public property and logger call shapes as computed compatibility accessors,
but route every delegate selection and library-logger generation through the
session.

## Problems

- A weak global delegate is read and written without synchronization.
- Concurrent logging can race delegate replacement or deallocation.
- `subsystem` and `libraryLogger` are independently mutable and can disagree.
- Delegate callbacks have no explicit rule for reentrancy or lock ownership.
- There is no terminal lifecycle or diagnostics for testing the global owner.
- FFmpeg and Metal debug output duplicate enable/write wrappers in thin policy
  files.
- The legacy FFmpeg variadic logger formats and prints through another
  forwarding-only policy.
- Existing tests only cover four sequential delegate callbacks and compare
  facade wrappers with the policy implementation.

## Goals

- Own process-wide logging configuration in one lock-protected session.
- Remove `nonisolated(unsafe)` from the public delegate property.
- Keep delegate storage weak while taking a strong snapshot for one delivery.
- Invoke delegates and fallback sinks only while the session lock is released.
- Permit a delegate callback to replace the delegate or log reentrantly.
- Publish a new default library logger atomically whenever the subsystem
  changes.
- Preserve explicit replacement of `libraryLogger`.
- Add active/closed phases, deterministic rejection after close, and complete
  diagnostics for the owner.
- Preserve `IRPlayerLogger`'s public initializer and four severity methods.
- Route compile-flag-enabled FFmpeg and Metal diagnostics through the library
  logger.
- Keep disabled diagnostics lazy and silent.
- Remove the FFmpeg log and FFmpeg/Metal runtime-debug forwarding policies.

## Non-Goals

- Change OSLog privacy formatting or add file/line metadata.
- Persist logging configuration.
- Guarantee a specific callback queue for a custom delegate.
- Retain a logging delegate.
- Close the process-wide system session during normal framework use.
- Change FFmpeg's process-lifetime network bootstrap policy.

## Components

### `IRPlayerLoggingSession`

The session owns:

- active or closed phase;
- normalized subsystem;
- the current default or explicitly supplied library logger;
- one weak delegate;
- monotonically increasing configuration and delegate generations;
- emission, delegate-delivery, fallback, rejection, and close counters.

Every emission takes one strong delegate snapshot and one delivery lease while
locked, then calls either the delegate or fallback sink after unlocking. The
lease records completion without retaining the delegate beyond that emission.

`close()` is terminal and idempotent. It clears the weak delegate and rejects
future emissions or configuration mutation. It does not wait on arbitrary
external delegate code; an already admitted callback keeps its strong snapshot
and records completion after close. Deinitialization invalidates silently.

### `IRPlayerLogger`

Each logger remains a value containing its immutable subsystem, category, and
OSLog sink. It also holds a weak reference to the logging session so a session
may own its current library logger without creating a retain cycle.

The public initializer binds to the process-wide system session. An internal
initializer permits deterministic session tests.

### Public Compatibility Accessors

`IRPlayerImp.Logger.subsystem`, `delegate`, and `libraryLogger` become computed
properties over the immutable process-wide session. Their source-level call
shape remains unchanged.

Changing `subsystem` constructs the replacement logger before locking and
publishes the subsystem/logger pair atomically. Assigning `libraryLogger`
replaces only the current logger value, preserving the configured subsystem.

### Runtime Debug Output

`IRFFRuntimeDebugOutput` and `IRMetalRuntimeDebugOutput` own their compile flag
directly. When disabled, they do not evaluate the message autoclosure. When
enabled, they send a debug message through
`IRPlayerImp.Logger.libraryLogger`.

Legacy FFmpeg variadic formatting remains at the FFmpeg boundary but no longer
requires a policy type. Invalid UTF-8 remains rejected before formatting.

## Invariants

- All mutable logging configuration is accessed under one session lock.
- No external delegate or fallback sink executes under that lock.
- One emission selects at most one delegate or one fallback sink.
- Delegate lifetime is weak between emissions and strong during one admitted
  callback.
- Subsystem replacement publishes one matching default logger generation.
- A logger does not retain its owning session.
- Reentrant logging and delegate replacement cannot deadlock.
- Close is terminal, repeatable, and clears the delegate.
- Disabled compile-time diagnostics remain silent and lazy.

## Testing

- Every public severity reaches a delegate with exact message and category.
- Delegate storage is weak and falls back after delegate deallocation.
- Delegate replacement and reentrant logging execute outside the lock.
- Subsystem replacement publishes a matching logger atomically.
- Explicit library logger replacement preserves its immutable configuration.
- Close clears the delegate, rejects mutation/emission, and is repeatable.
- Concurrent logger reads, configuration mutation, delegate replacement,
  emission, and close preserve coherent diagnostics under Thread Sanitizer.
- Disabled FFmpeg and Metal output does not evaluate messages or print.
- FFmpeg variadic formatting accepts valid input and rejects invalid UTF-8.
- Existing frame-pool logging and public logger source compatibility remain.

## Acceptance Criteria

- No first-party `nonisolated(unsafe)` logging state remains.
- Logging configuration has one explicit synchronized owner.
- `IRFFLogPolicy.swift`, `IRFFRuntimeDebugOutputPolicy.swift`, and
  `IRMetalRuntimeDebugOutputPolicy.swift` are removed.
- Changed source emits no warnings.
- Focused tests, Thread Sanitizer, the full simulator suite, and a generic iOS
  device Release build pass.
