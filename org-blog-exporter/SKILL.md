---
name: org-blog-exporter
description: >-
  Export or explicitly publish configured Org notes as static HTML through Emacs, including local
  resources, generated commits, and pushes for authorized publishing.
---

# Org Blog Exporter

Load `scripts/org-blog-exporter.el` and call `org-blog-exporter-run` through the
running Emacs server.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Resolve ambiguous files before acting. Treat publish as authorized only when the
user explicitly requested it. Never bypass a facade safety error manually.
