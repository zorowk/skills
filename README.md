# AI Skills

一组面向 AI 助手的本地 skills。它们把可靠性约束、运行中的 Emacs 状态，以及
Denote、HyWiki、Org GTD、Org 导出和 Magit 等能力封装成可验证的工作流。

## Skills

| Skill | 功能 | 典型请求 |
| --- | --- | --- |
| [`ai-constitution`](ai-constitution/SKILL.md) | 在复杂、不确定或高影响任务中应用轻量可靠性原则：先理解和验证，再执行最小、可逆的改动；简单任务仍保持直接。 | “严格分析这个问题并验证结论” |
| [`denote-scribe`](denote-scribe/SKILL.md) | 将已完成的排障、开发或研究对话保存为中英文 Denote 批判性思考笔记；按 Git 提交节奏执行 AI Review，将成熟概念提炼到 HyWiki，并通过非交互式 Magit 提交本次生成的文件。 | “输出 Denote 报告” |
| [`emacs-code-navigator`](emacs-code-navigator/SKILL.md) | 将运行中的 Emacs 作为能力注册表和代码上下文来源：搜索函数、命令、变量与库，读取 Help 文档并定位源码，同时支持未保存的 buffer、项目搜索、Imenu、逐行 xref、Eldoc/Eglot 和 Flymake 诊断。 | “Emacs 里有什么函数能完成这个任务？”“查看这个符号的文档和源码” |
| [`emacs-gtd-assistant`](emacs-gtd-assistant/SKILL.md) | 通过 Emacs 管理 `~/Dropbox/brain/gtd.org`：列出或查找任务，新增、改状态、重新排期、设置截止日期，以及经明确授权后删除或归档。 | “列出今天的任务”“把这个任务标记为 DONE” |
| [`org-blog-exporter`](org-blog-exporter/SKILL.md) | 将 `~/Dropbox/notes` 中符合条件的 Org 笔记导出为静态 HTML；支持单篇、批量和全量导出。明确要求发布时，还可更新索引、复制并重写本地资源、提交并推送博客仓库。 | “预览这篇 Org 笔记”“发布博客” |
| [`git-commit`](git-commit/SKILL.md) | 为任意仓库生成便于 AI 和人理解的提交信息；从实际 diff 提炼证据，按风险自动选择详细度，并执行 100 列校验。 | “生成 commit message”“提交这些修改” |

每个目录中的 `SKILL.md` 只保留触发条件、需要模型判断的规则和授权边界；可确定执行的
流程由 `scripts/*.el` 的公共函数、docstring 与校验错误构成。正常使用时无需让助手通读
实现源码。

每个 Emacs 集成 skill 提供一个 compact 主入口：Navigator 限制 Help 长度，GTD 和博客
限制列表结果，Git Commit 限制 diff 总量，Denote Review 分页返回关键章节。旧公共函数继续
保留，完整上下文只在 compact 结果不足时按需请求。

主入口统一返回 `:status`、`:operation`、`:count` 和 `:data`；分页结果增加 `:page`，副作用
增加 `:effects`。截断和下一页位置均为机器可读字段。仅在调用参数不明确时请求
`describe` schema，无需读取实现源码。

## 主要工作流

### Denote、AI Review 与 HyWiki

`denote-scribe` 不只是生成一个看起来像 Denote 的文件名，而是实际调用 Denote：

1. 根据对话语言选用中英文批判性笔记模板，区分证据、推断、反证和不确定性。
2. 创建 Denote Org 笔记，并检查距离上次 AI Review 的 Git 提交数；首次运行会进行全量 bootstrap review。
3. 先复查未解决和已解决的问题，再评估概念。只有具备可解释模型、可追溯依据、复用价值和清晰边界的成熟概念才会进入 HyWiki；一次有效 review 可以不生成概念页。
4. 通过共享 formatter 提交本次新建的 Denote 笔记和变更的 HyWiki 页面。skill 不会 push。

默认目录为 `~/Dropbox/notes/`、`~/Dropbox/hywiki/` 和 Git 仓库
`~/Dropbox/`；默认每 5 次仓库提交触发一次 review，均可通过 Emacs
custom variables 调整。Review 默认每页返回 8 篇笔记，每个关键章节最多 500 个字符；
调用方应遍历所有分页，仅对截断或有争议的证据读取全文。

### Org 博客导出与发布

`org-blog-exporter` 会跳过草稿、私有目录及带 `draft`、`private` 或
`noexport` 标签的笔记。导出时可使用 `setupfile.org` 配置 HTML；发布时还会：

- 更新博客索引；
- 将 Org 中引用的图片、音视频、PDF 等本地资源复制到仓库的 `image/` 目录，并重写导出副本中的链接；
- 仅提交本次生成的 HTML、索引和资源，然后推送配置的仓库。

Denote、博客发布和普通仓库提交共享同一套结构化证据、自然正文和 100 列 formatter；
低风险小改动自动压缩正文，高风险或多项修改保留完整边界。

导出不会隐式发布。只有用户明确要求“发布”时，skill 才能执行 clone、commit 和
push 流程。

## Requirements

通用的 Emacs 集成要求：

- `emacsclient` 位于 `PATH`，且已有运行中的 Emacs server；
- 对应 Emacs 功能在该 session 中可用。

额外依赖如下：

- `denote-scribe`：Denote、HyWiki、Magit，以及包含 `notes/` 和 `hywiki/` 的 Git 仓库；
- `emacs-code-navigator`：Emacs 的 `project`、`xref`、Imenu；Eglot 和 Flymake 为按需能力；
- `emacs-gtd-assistant`：Org mode 和已有的 GTD 文件及目标 heading；
- `org-blog-exporter`：Org HTML exporter；发布流程还需要 Magit、Git 仓库和远端权限；
- `git-commit`：Magit（用于从任意当前仓库收集提交证据）；
- `ai-constitution`：无额外运行时依赖。

## Install

将需要的 skill 目录复制或软链接到客户端使用的 skills 目录。仓库结构需要保留；
所有 Emacs skill 都会从同级 `common/` 加载统一返回协议；提交相关 skill 还会加载共享
Git formatter，因此安装任意 Emacs skill 时必须保留 `common/`。

例如，为 Codex 安装整个仓库时，可让目标目录包含：

```text
skills/
├── common/
├── ai-constitution/
├── denote-scribe/
├── emacs-code-navigator/
├── emacs-gtd-assistant/
├── org-blog-exporter/
└── git-commit/
```

如果客户端支持导入压缩包，可按需打包。下面的示例包含全部 skills：

```bash
zip -r ai-skills.zip \
  common ai-constitution denote-scribe emacs-code-navigator \
  emacs-gtd-assistant org-blog-exporter git-commit
```

启用或重新加载 skills 后，直接用自然语言提出表格中的请求即可。涉及删除、归档、
发布、提交或推送的操作仍受各 skill 的授权和安全检查约束。

开发修改后可运行统一契约测试：

```bash
emacs -Q --batch -l tests/skill-contract-tests.el \
  -f ert-run-tests-batch-and-exit
```
