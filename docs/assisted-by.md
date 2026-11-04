# Assisted-by 0.1

Declares which AI tool and model helped with a pull request. It feeds public statistics. It is self-reported and cannot be verified, so those statistics show trends only.

## Format

One `Assisted-by` line per tool, at the end of the PR body:

```
Assisted-by: <tool>[/<version>] (<provider>/<model>)
Assisted-by: <tool>[/<version>] (unknown)
Assisted-by: none
```

Examples:

```
Assisted-by: claude-code/2.1.316 (anthropic/claude-opus-4-8)
Assisted-by: cursor (openai/gpt-5.5)
Assisted-by: aider (unknown)
Assisted-by: none
```

Tool, provider and model are lowercase. Use `unknown` when neither the agent nor its human can tell which model ran. Use `none` alone, for a PR written with no AI.

Validation pattern:

```
^(none|(?!none[ /])[a-z0-9][a-z0-9._-]*(/[A-Za-z0-9._-]+)? \(([a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*|unknown)\))$
```

## In the repository

1. The human responsible for the PR confirms the value.
2. CI refuses a PR with a missing or malformed line. An unknown tool or model only gives a warning.
3. `ai-tools.toml` maps variants to one name. It is admin-only.
4. The merge bot copies the lines to the end of the squash commit message. The commit on `main` is the reference.
5. A job reads the history and generates the statistics:

```
git log --format='%(trailers:key=Assisted-by,valueonly)' main
```

No access or vote may depend on the declared model.
