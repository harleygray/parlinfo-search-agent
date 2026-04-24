# Elixir Anti-Patterns Checker

Check Elixir files for anti-patterns from the official Elixir documentation.

## Instructions

1. **Determine target files:**
   - If `$ARGUMENTS` are provided, use those file paths
   - Otherwise, get recently changed files via: `git diff --name-only HEAD` and `git diff --name-only --staged`
   - Filter to only `.ex` and `.exs` files

2. **Read each target file** using the Read tool.

3. **Review each file** against the anti-pattern checklist below. For each finding, report:
   - `file_path:line_number` reference
   - Anti-pattern name (from the checklist)
   - Brief explanation of the issue
   - Suggested refactoring

4. **Output format:**
   ```
   ## Anti-Pattern Findings

   ### file_path.ex

   - **line 42** — *Complex else in with*: The `with` statement has a complex `else` block handling multiple error patterns. Consider splitting into separate functions or using pattern matching outside `with`.

   ### file_path2.ex

   No anti-patterns found.
   ```

5. If no anti-patterns are found in any file, say so clearly.

## Anti-Pattern Checklist

### Code-related

- **Comments overuse**: Excessive comments that restate what code already expresses. Prefer self-documenting function/variable names.
- **Complex else in with**: `with` statements with large `else` blocks handling many error clauses. Extract error handling or use dedicated functions.
- **Complex extractions in clauses**: Overly complex pattern matching in function heads or case clauses. Extract to intermediate variables or helper functions.
- **Dynamic atom creation**: Using `String.to_atom/1` or interpolation to create atoms dynamically, risking atom table exhaustion. Use `String.to_existing_atom/1` or module attributes instead.
- **Long parameter list**: Functions with too many parameters (5+). Group related params into maps or structs.
- **Namespace trespassing**: Accessing internal modules of another context directly (e.g., `OtherContext.Internal.Module.func()`). Use the context's public API.
- **Non-assertive map access**: Using `map[:key]` when the key is expected to exist. Use `map.key` or `Map.fetch!/2` to fail fast on missing keys.
- **Non-assertive pattern matching**: Using overly permissive patterns (e.g., `_` or bare variables) when a more specific match would catch bugs earlier.
- **Non-assertive truthiness**: Relying on truthiness (`if value`) when an explicit boolean or pattern match is clearer and safer.
- **Structs with 32+ fields**: Structs with too many fields indicating the need to decompose into smaller structs.

### Design-related

- **Alternative return types**: Functions that return different shapes (e.g., sometimes a list, sometimes a single item). Be consistent with return types.
- **Boolean obsession**: Using multiple boolean parameters or complex boolean logic instead of atoms, enums, or pattern matching.
- **Exceptions for control-flow**: Using `raise`/`rescue` for expected conditions. Use tagged tuples (`{:ok, _}` / `{:error, _}`) instead.
- **Primitive obsession**: Passing raw strings/integers where a struct or dedicated type would provide clarity and validation.
- **Unrelated multi-clause function**: Function clauses that handle fundamentally different concerns. Split into separate functions.
- **Application config for libraries**: Libraries reading from `Application.get_env/3` instead of accepting config via function parameters.

### Process-related

- **Code organization by process**: Organizing modules around processes (GenServer, Agent) rather than around domain concepts.
- **Scattered process interfaces**: Process interactions (GenServer.call, send, etc.) spread across many modules instead of being encapsulated in one module.
- **Sending unnecessary data**: Sending large data structures between processes when only a subset is needed.
- **Unsupervised processes**: Spawning processes with `spawn/1` or `Task.start/1` without supervision. Use `Task.Supervisor` or add to a supervision tree.

### Meta-programming

- **Compile-time dependencies**: Unnecessary compile-time deps via `require` or struct references that cause cascading recompilations.
- **Large code generation**: Macros generating excessive amounts of code, making debugging difficult.
- **Unnecessary macros**: Using macros where a function would suffice. Prefer functions over macros.
- **`use` instead of `import`**: Using `use` when only `import` is needed, pulling in unnecessary code.
- **Untracked compile-time dependencies**: Reading external files or env vars at compile time without declaring them via `@external_resource`.
