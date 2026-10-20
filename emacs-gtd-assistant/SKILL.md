---
name: emacs-gtd-assistant
description: >
  Work from user-selected Org/Agenda projects and tasks: link project documents,
  turn an agreed design into implementation subtasks, read task/session context,
  and save progress or handoffs through Emacs. Also manage existing Org tasks.
  Do not create follow-up tasks merely because they appear in conversation.
---

# Emacs GTD Assistant

The user chooses goals and work. Org project/task entries are the implementation
plan and progress record; project repositories retain requirements, architecture,
and other durable documents, linked from the project entry. Do not create a
second implementation-plan document unless the user requests one.

Discussion may precede any task breakdown. Read existing project documents and
code before drafting a breakdown. When the user asks to create the breakdown,
write actionable child tasks with acceptance criteria under the selected parent;
existing explicit authorization is sufficient. Merely discussing possible next
steps does not authorize creating tasks. Do not limit a requested project
breakdown to the small conversation-capture limit.

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-gtd-assistant.el")
  (emacs-gtd-execute REQUEST))
```

Use `describe` for the relevant operation's schema when needed. `get` reads a
known ID's own entry, nearest project, resource links and session history.
`create-project` / `configure-project` establish a project directory and links;
`add-children` writes unscheduled implementation tasks below an explicit parent ID.
The facade manages explicitly configured files, validates requests, disambiguates
identities, and owns all Org mutations. Never bypass it to edit managed Org.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

When a task ID is supplied by agent-shell, use it as the current work item; do
not infer identity from a buffer name, similar title, or project directory alone.
Keep work within the user's current instruction. Read linked documents as needed;
URLs and links are references, not proof that their contents have been read.

For an authorized wrap-up, verify the actual changes and validation, then use
`add-note` for dated results, blockers and useful references, and `set-context`
for the short current handoff. Do not save the full transcript in Org. Do not
mark DONE just because the agent finished a turn; use DONE when the user accepts
the result or explicitly requests that state. Do not implicitly commit or push.

Store queryable metadata in `:properties`, short handoffs in `:context-notes`,
and repository/document references in structured `:links`. `set-links` replaces
that entry's resources: read and preserve existing links when adding one.
For ordinary task capture, use `add` / `add-many` with explicit authorization.

For the human-facing commands, data conventions and example, read
[references/workflow.org](references/workflow.org) when setting up or explaining
the Org/agent-shell integration.
