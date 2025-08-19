# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Finitomata is an Elixir library that provides FSM (Finite State Machine) boilerplate based on callbacks. It allows developers to define FSMs using PlantUML or Mermaid syntax and generates a GenServer implementation with validation and consistency checking.

### Key Components

- **Finitomata**: Core FSM implementation for single-node operations
- **Infinitomata**: Distributed FSM implementation that runs transparently across clusters using `:pg` process groups
- **Finitomata.Flow**: Flow-based FSM operations using GenStage
- **Finitomata.Pool**: Asynchronous FSM pool management
- **Finitomata.Cache**: Caching layer for FSM states
- **Finitomata.Throttler**: Rate limiting and throttling capabilities
- **Finitomata.ExUnit**: Testing utilities for FSM implementations

## Development Commands

### Dependencies and Compilation
```bash
# Install dependencies
mix deps.get

# Compile the project (includes custom :finitomata compiler)
mix compile

# Get dependencies and compile in one step
mix do deps.get, deps.compile, compile
```

### Testing
```bash
# Run all tests (excludes distributed and finitomata env tests)
mix test

# Run only standard tests (excludes distributed tests)
mix test --exclude distributed --exclude finitomata

# Run distributed tests only
mix test --exclude test --include distributed

# Run tests in finitomata environment (special test env for the library)
MIX_ENV=finitomata mix do deps.get, deps.compile, compile
MIX_ENV=finitomata mix test --exclude test --include finitomata

# Test specific examples
cd examples/ecto_integration && mix test
cd examples/caches && mix test
cd examples/ex_unit_testing && mix test
cd examples/telemetria && mix test
```

### Quality Assurance
```bash
# Run formatting, credo, and dialyzer
mix quality

# CI version (with format checking)
mix quality.ci

# Individual QA tasks
mix format                           # Format code
mix credo --strict                  # Static code analysis
mix dialyzer --unmatched_returns    # Type checking
```

### Code Generation
```bash
# Generate test scaffolding for FSM modules
mix finitomata.generate.test --module MyApp.FSM
```

## Architecture

### FSM Definition
FSMs are defined using either Mermaid flowchart syntax (default) or PlantUML state diagram syntax:

**Mermaid (`:flowchart`)**:
```
s1 --> |to_s2| s2
s1 --> |to_s3| s3
```

**PlantUML (`:state_diagram`)**:
```
[*] --> s1 : to_s1
s1 --> s2 : to_s2
s1 --> s3 : to_s3
s2 --> [*] : ok
s3 --> [*] : ok
```

### Core Callbacks
- `on_transition/4` - **mandatory** callback for state transitions
- `on_failure/3` - optional failure handling
- `on_enter/2` - optional state entry callback
- `on_exit/2` - optional state exit callback
- `on_terminate/1` - optional termination callback
- `on_timer/2` - optional timer callback

### Special Event Types
- Events ending with `!` (e.g., `start!`) are determined transitions that execute immediately
- Events ending with `?` (e.g., `start?`) are soft transitions that don't log failures

### Distributed Operations (Infinitomata)
Uses `:pg` process groups for cluster coordination. Requires implementing `Finitomata.ClusterInfo` behavior for custom node discovery.

## Test Structure

### Test Environments
- `:test` - Standard test environment
- `:finitomata` - Special environment for testing the library itself
- `:ci` - Continuous integration environment

### Test Categories
- **Standard tests**: Regular unit and integration tests
- **Distributed tests**: Cluster and multi-node functionality (tagged with `:distributed`)
- **Finitomata tests**: Internal library tests (tagged with `:finitomata`)

### Test Support Modules
Located in `test/support/` directory, included in test and dev environments.

## Configuration

### Application Configuration
- Supports different start modes: `Finitomata`, `Infinitomata`, or nil for no auto-start
- Configurable telemetry integration with `telemetria`
- Mock support for testing environments

### Compiler Configuration
Uses a custom `:finitomata` compiler that validates FSM definitions at compile time and provides warnings for unimplemented ambiguous transitions.

## Documentation and Examples

### Examples Directory
- `ecto_integration/` - Ecto database integration patterns
- `caches/` - Caching implementation examples  
- `ex_unit_testing/` - ExUnit testing utilities
- `telemetria/` - Telemetry integration examples

### Documentation Generation
Uses ExDoc with custom Mermaid diagram rendering support for FSM visualizations.

## Dependencies

### Core Dependencies
- `nimble_parsec` - Parser combinator for FSM syntax
- `gen_stage` - Producer-consumer pipelines for Flow
- `estructura` - Struct validation and coercion

### Optional Dependencies
- `telemetry` + `telemetry_poller` - Metrics and monitoring
- `telemetria` - Telemetry wrapper

### Development Dependencies
- `nimble_ownership` + `mox` - Testing utilities
- `stream_data` - Property-based testing
- `credo` - Static analysis
- `dialyxir` - Type checking

## Important Notes

- The project uses OTP version detection to conditionally include modern libraries
- Requires Elixir ~> 1.14 and supports OTP 25+  
- Uses epmd daemon for distributed testing
- Custom formatter configuration for FSM-specific macros
- Postgres service required for some example tests
