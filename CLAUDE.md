# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

## Project Overview

BiteLog is an iOS application for meal tracking and nutrition management. Built with SwiftUI and SwiftData, it manages food nutrition data and records daily meals.

The repository also contains web apps under `apps/`: `apps/web/` (React SPA on Cloudflare Pages), `apps/docs/` (React SSG on Cloudflare Pages), and `cloudflare/` (Hono API on Cloudflare Workers + D1).

## ワークフロー設計

### 1. Planモードを基本とする

- 3ステップ以上 or アーキテクチャに関わるタスクは必ずPlanモードで開始する
- 途中でうまくいかなくなったら、無理に進めずすぐに立ち止まって再計画する
- 構築だけでなく、検証ステップにもPlanモードを使う
- 曖昧さを減らすため、実装前に詳細な仕様を書く

### 2. サブエージェント戦略

- メインのコンテキストウィンドウをクリーンに保つためにサブエージェントを積極的に活用する
- リサーチ・調査・並列分析はサブエージェントに任せる
- 複雑な問題には、サブエージェントを使ってより多くの計算リソースを投入する
- 集中して実行するために、サブエージェント1つにつき1タスクを割り当てる

### 3. 自己改善ループ

- ユーザーから修正を受けたら必ず `tasks/lessons.md` にそのパターンを記録する
- 同じミスを繰り返さないように、自分へのルールを書く
- ミス率が下がるまで、ルールを徹底的に改善し続ける
- セッション開始時に、そのプロジェクトに関連するlessonsをレビューする

### 4. 完了前に必ず検証する

- 動作を証明できるまで、タスクを完了とマークしない
- 必要に応じてmainブランチと自分の変更の差分を確認する
- 「スタッフエンジニアはこれを承認するか？」と自問する
- テストを実行し、ログを確認し、正しく動作することを示す

### 5. エレガントさを追求する（バランスよく）

- 重要な変更をする前に「もっとエレガントな方法はないか？」と一度立ち止まる
- ハック的な修正に感じたら「今知っていることをすべて踏まえて、エレガントな解決策を実装する」
- シンプルで明白な修正にはこのプロセスをスキップする（過剰設計しない）
- 提示する前に自分の作業に自問自答する

### 6. 自律的なバグ修正

- バグレポートを受けたら、手取り足取り教えてもらわずにそのまま修正する
- ログ・エラー・失敗しているテストを見て、自分で解決する
- ユーザーのコンテキスト切り替えをゼロにする
- 言われなくても、失敗しているCIテストを修正しに行く

---

## タスク管理

1. **まず計画を立てる**：チェック可能な項目として `tasks/todo.md` に計画を書く
2. **計画を確認する**：実装を開始する前に確認する
3. **進捗を記録する**：完了した項目を随時マークしていく
4. **変更を説明する**：各ステップで高レベルのサマリーを提供する
5. **結果をドキュメント化する**：`tasks/todo.md` にレビューセクションを追加する
6. **学びを記録する**：修正を受けた後に `tasks/lessons.md` を更新する

---

## コア原則

- **シンプル第一**：すべての変更をできる限りシンプルにする。影響するコードを最小限にする。
- **手を抜かない**：根本原因を見つける。一時的な修正は避ける。シニアエンジニアの水準を保つ。
- **影響を最小化する**：変更は必要な箇所のみにとどめる。バグを新たに引き込まない。

## Situation-specific guides (skills)

Detailed, situational guidance lives in skills under `.claude/skills/` and is
loaded on demand. Use the matching skill when the work calls for it:

- **ios-development** — building/running/debugging the iOS app (SweetPad commands, required tools), data models and view structure
- **web-admin-console** — working under `apps/web/`, `apps/docs/`, or `cloudflare/` (local dev, auth, Hono RPC, tests, Cloudflare deploy)
- **tdd-testing** — writing tests / implementing features test-first (t-wada's TDD)

## Development Flow

1. Create a GitHub issue describing the problem (why)
2. Branch from up-to-date main — run `git fetch origin main` first; local main may be stale
3. Open a PR with `Closes #N`. Verify the actual diff with `gh pr diff` before writing the description

## Commit Message Guidelines

### t-wada's Philosophy

- **Code**: How (implementation details)
- **Test code**: What (what is being tested)
- **Commit log**: Why (reason for change)
- **Code comments**: Why not (why other approaches weren't used)

### Format

```
<type>: <subject>

<body: explain why this change is needed>
```

**type**: feat, fix, docs, style, refactor, test, chore
**subject**: 50 chars max, imperative mood, Japanese OK
