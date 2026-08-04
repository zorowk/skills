---
name: org-blog-exporter
description: >-
  Export or publish configured Org notes as static HTML through Emacs, including local resources
  and verified Git publication. Use only when the user explicitly requests export or publication.
---

# Org Blog Exporter

```text
export?  := explicit export or publish request
publish? := explicit publish request AND explicit authorization
mutate?  := explicit authorization AND unambiguous sources
            AND requested operation permits its effects
done?    := requested outputs and repository effects pass verification
```

Invoke the facade with one self-loading expression; `REQUEST` is a plist beginning
with `:operation`:

```elisp
(progn
  (load-file "<skill-dir>/scripts/org-blog-exporter.el")
  (org-blog-exporter-run REQUEST))
```

## Execution and recovery

```text
known schema       -> call operation directly
unknown schema     -> describe(target), then call
invalid-request #1 -> describe(target), revise once
invalid-request #2 -> stop
partial            -> preserve evidence/effects; retry only the safe remainder
stop               -> report effects and remaining goal; no more facade calls
```

Send only schema-declared fields. Inspect the script only if the entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

## Completion

```text
export_done :=
  every source has an existing output
  AND public-note policy passed
  AND rewritten asset links passed

publish_allowed := user explicitly requested publish
publish_done :=
  publish_allowed
  AND export_done
  AND index and planned assets verified
  AND path-scoped commit exists when changes occurred
  AND upstream commit = pushed commit
```

Use existing public Org files below `:notes-dir`. `publish` exports, commits generated
files in `:repository-dir`, and pushes the configured upstream. Resolve ambiguous
files before acting; never bypass a facade safety error. Use `:verification`, not
tool-call success, as completion evidence.

If index generation fails, do not commit or push. A resource or index failure after
HTML generation is partial success: report effects, leave commit and push unset,
and do not retry the whole publish blindly.
