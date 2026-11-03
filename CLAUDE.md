# CLAUDE.md — SAGANA Development Guidelines

## 1. Project Context

- SAGANA is a Flutter mobile-based Agriculture Marketplace and Farm Management System using Supabase and PostgreSQL.
- Roles: Manager (`admin`), Officer, Farmer, and Buyer.
- Chrome is used for development/testing, not as the application's product classification.
- Follow existing project architecture, conventions, and role permissions.
- Inspect relevant source files when project details are needed.

## 2. Task Understanding

- Fully understand the user's request before implementation.
- Identify affected modules, dependencies, and expected behavior.
- Check existing functionality before proposing changes.
- Do not ask questions that can be answered through the codebase or database.
- Ask only when an essential business decision remains unresolved.

## 3. Codebase Investigation

- Inspect only files relevant to the current task.
- Trace existing UI, repositories, services, RPCs, and database relationships.
- Reuse existing functionality instead of duplicating logic.
- Verify assumptions against actual implementation.
- Avoid unnecessary full-project searches and unrelated files.
- Do not inspect `.claude-scratch/` unless relevant.

## 4. Implementation

- Implement the requested functionality completely.
- Preserve existing working features and role restrictions.
- Follow established Flutter/Dart architecture.
- Avoid unnecessary refactoring and hardcoded business rules.
- Keep changes focused on the requested scope.
- Update dependent modules when necessary.
- Do not silently change unrelated workflows.

## 5. Important Business Rules

- Preserve Manager, Officer, Farmer, and Buyer permissions.
- Manager and Officer share applicable management workflows, subject to existing restrictions.
- Enforce business-critical validations in Supabase, not only Flutter.
- Prevent duplicate transactions, stock deductions, and invalid state transitions.
- Preserve existing offline/online restrictions.
- Do not invent unconfirmed cooperative policies.
- Use configured crop market types and selling channels instead of hardcoding crop names.

## 6. Database & Supabase

- Inspect relevant Supabase tables, views, RLS policies, functions, triggers, and RPCs.
- Verify existing database logic before modifying it.
- Preserve data integrity and transaction safety.
- Provide exact SQL scripts for required database changes.
- SQL scripts are executed manually by the user.
- Never assume newly generated SQL has already been applied.
- Avoid reapplying outdated SQL that may overwrite newer database behavior.
- Verify Flutter and database compatibility.

## 7. UI/UX Design

- Follow SAGANA's existing branding and design system.
- Improve layouts, spacing, alignment, typography, forms, dialogs, and navigation where relevant.
- Prioritize clean, modern, intuitive, and mobile-friendly interfaces.
- Maintain consistent designs across related modules.
- Provide clear loading, empty, success, error, and validation states.
- Make independent minor design decisions.
- Preserve accessibility, functionality, and role restrictions.
- Update English and Tagalog localization for user-facing text.
- Use AppToast for messages displayed over dialogs.

## 8. Error Handling & Testing

- Investigate root causes instead of applying temporary workarounds.
- Handle loading, network, database, and validation errors appropriately.
- Prevent duplicate submissions and invalid operations.
- Verify related functionality after changes.
- Run relevant Flutter analysis and tests.
- Report tests that cannot be executed instead of claiming success.

## 9. Token Efficiency

- Keep responses concise and task-focused.
- Inspect relevant files rather than repeatedly reading the entire project.
- Avoid redundant explanations and unnecessary tool calls.
- Do not generate excessive documentation unless requested.
- Reuse existing context when reliable.
- Summarize findings instead of dumping large file contents.
- Avoid unrelated refactoring or investigation.

## 10. Final Verification

After every implementation, provide a structured report covering:

### Implementation Summary
1. **What was changed** — Summarize completed implementations and fixes.
2. **Complete list of modified files** — Include all created, modified, and deleted files with their purposes.
3. **Dart file changes** — Explain relevant Flutter/Dart modifications.
4. **SQL/database changes** — List affected tables, RPCs, functions, triggers, RLS policies, and required SQL scripts in execution order.
5. **Required database checks** — Identify database changes or conditions requiring manual verification.
6. **Pending decisions or approvals** — Clearly identify anything requiring the user's decision or approval.

### Testing and Verification
1. **What to test** — Identify affected functionality and relevant regression scenarios.
2. **Exact testing steps** — Provide step-by-step instructions the user can follow.
3. **Expected results** — State the expected outcome for each test.
4. **Database/SQL checks** — Provide exact SQL queries when database verification is necessary.
5. **Cross-module and cross-role testing** — Include affected modules, dependencies, and relevant Manager, Officer, Farmer, and Buyer scenarios.

### Verification Rules
- Run relevant automated checks and report their actual results.
- Distinguish completed, partially implemented, and pending functionality.
- Clearly separate verified results from untested assumptions.
- Never claim successful testing or completion without evidence.
- Keep the report concise but complete; do not omit important changes or verification steps.

Do not claim completion without checking the implementation.