# XWXTodo Design

Date: 2026-05-06
Status: Draft approved in conversation

## Summary

XWXTodo is a macOS 14+ local-first TODO app for keeping the current task visible without requiring the user to remember opening Notes or another TODO tool.

The app keeps a small black notch-like overlay at the physical top center of the primary display. The overlay shows the active TODO title. When no TODO is active, it shows `XWXTodo`. Hovering over the notch replaces it with a dropdown panel from the top edge of the screen. The panel contains the main TODO list and the controls needed to add, edit, delete, start, and complete TODO items.

The first version is intended as a local utility that can be zipped and shared directly. It is not designed for the Mac App Store. It does not include networking, syncing, accounts, built-in auto-start, signing, notarization, or automatic updates.

## Goals

- Record, edit, and delete active TODO items.
- Mark exactly one TODO as the current active item.
- Mark TODO items as completed.
- Keep completed TODO items out of the main list.
- Provide a Completed List for read-only history.
- Store all data locally in SQLite.
- Keep the top overlay visible at the primary display's physical top edge across desktop, normal apps, and full-screen app spaces where macOS allows it.
- Preserve a Dock icon in the first version.

## Non-Goals

- App Store distribution.
- Cloud sync or any network feature.
- User accounts.
- Menu bar extra as a second primary entry point.
- Built-in login item or auto-start switch.
- Multi-display overlays.
- Recovery, editing, or deletion from the Completed List.
- Drag-and-drop ordering in the first version.
- Accessibility, screen recording, or input monitoring permissions unless later implementation testing proves they are unavoidable.

## Product Interaction

The app has two visible overlay states:

1. Collapsed notch
   - Displayed at the primary display's physical top center.
   - Black background.
   - Shows the current active TODO title.
   - Shows `XWXTodo` when no TODO is active.
   - Long titles are truncated to one line.

2. Expanded panel
   - Triggered by hovering over the collapsed notch hot zone.
   - Replaces the notch; the notch is not separately visible under or above the panel.
   - Starts at the physical top edge of the screen.
   - Contains the input and list controls.
   - Collapses back to the notch when the pointer leaves the expanded panel region.

The expanded panel supports:

- Adding a TODO.
- Editing a TODO title.
- Deleting a pending or active TODO.
- Starting a TODO, which makes it the only active item.
- Completing a TODO.
- Viewing the Completed List.

The main TODO list shows only `pending` and `doing` items. Completed items are hidden from the main list and visible only in the Completed List. The Completed List is read-only in the first version.

## Architecture

The first version should use native macOS technologies:

- SwiftUI for the app shell and panel content.
- AppKit for the top-level overlay window behavior.
- SQLite for local persistence.

Primary modules:

- `XWXTodoApp`
  - SwiftUI app entry point.
  - Keeps the Dock icon.
  - Starts the main app lifecycle and overlay controller.

- `OverlayController`
  - AppKit-owned controller for the collapsed notch and expanded panel.
  - Positions the overlay on the primary display.
  - Handles hover regions, expand/collapse transitions, and window level.
  - Uses borderless, non-activating floating panels where appropriate.
  - Adds the overlay to all spaces and supports full-screen auxiliary behavior.

- `TodoStore`
  - Business state layer.
  - Exposes add, edit, delete, start, complete, and query operations.
  - Enforces the single active TODO rule.
  - Keeps SwiftUI views independent from SQLite details.

- `SQLiteTodoRepository`
  - Owns local SQLite access.
  - Initializes and migrates the database.
  - Performs CRUD operations and transactional state changes.

- `SwiftUI Views`
  - Render the collapsed notch content and expanded panel content.
  - Keep UI behavior declarative and route mutations through `TodoStore`.

The main separation is intentional: AppKit owns system window behavior, SwiftUI owns list rendering and interaction, and the store/repository layers own state consistency and persistence.

## Overlay Behavior

The overlay is not part of the desktop, the main window, or the active app's content area. It is a separate system-level overlay owned by XWXTodo.

Implementation should start with an AppKit `NSPanel` or equivalent borderless window configured as:

- Borderless.
- Non-activating where possible.
- Floating above ordinary app windows.
- Joined to all spaces.
- Full-screen auxiliary capable.
- Positioned relative to the primary display frame, not a content window frame.

Implementation must explicitly verify:

- Desktop visibility.
- Normal app visibility.
- Full-screen app visibility.
- Space switching behavior.
- Whether the panel steals focus.
- Whether hover tracking still works over full-screen apps.

If full-screen apps obscure the overlay, implementation may raise the window level while preserving the constraints that the overlay remains small, non-disruptive, and does not request unnecessary permissions.

## Data Model

`TodoItem`:

- `id: UUID`
- `title: String`
- `status: pending | doing | completed`
- `createdAt: Date`
- `updatedAt: Date`
- `completedAt: Date?`
- `sortOrder: Int`

Rules:

- `title` is trimmed before save.
- Empty titles are not saved.
- At most one item may have `doing` status.
- Starting an item changes the previous `doing` item back to `pending`.
- Completing an item sets `status = completed` and writes `completedAt`.
- Completed items do not appear in the main TODO list.
- Completed items are shown by `completedAt` descending.
- Pending and doing items are shown by `sortOrder`.
- Delete is available only for pending and doing items.

SQLite should reinforce the single `doing` rule with transactional updates. A partial unique index for `doing` status is acceptable if it fits the SQLite version available through the chosen integration.

## Storage

The app stores data only on the local machine.

Default database location:

```text
~/Library/Application Support/XWXTodo/xwxtodo.sqlite
```

The repository should create the application support directory and database on first launch. Schema creation and migrations should be idempotent.

No network stack, account storage, analytics, telemetry, or sync service should be added in the first version.

## Error Handling

- If the database cannot open or migrate, the app should avoid crashing where possible.
- In database failure mode, the notch can still show `XWXTodo`, and the main window or panel should present a clear local error.
- Empty titles should not save; the input remains editable without a disruptive alert.
- Long titles should be truncated in the notch and list rows.
- The full title should remain visible while editing.
- If there are no TODOs, the expanded panel shows an empty state and the add input.
- If there are TODOs but no active item, the notch shows `XWXTodo`.

## Distribution

The first version is distributed as a zipped `.app`.

The initial distribution workflow only needs to produce:

```text
XWXTodo.app
XWXTodo.zip
```

Signing, notarization, Sparkle updates, and App Store packaging are outside the first version.

## Testing And Acceptance

Unit tests should cover `TodoStore` behavior:

- Add TODO.
- Edit TODO.
- Delete pending or doing TODO.
- Start TODO.
- Ensure only one `doing` item exists.
- Complete TODO.
- Filter main list.
- Filter completed list.

Database tests should cover:

- Database initialization.
- CRUD persistence.
- Transactional `doing` switching.
- `completedAt` persistence.
- Completed list ordering.
- Data surviving app restart.

Manual UI acceptance should cover:

- Dock icon is present.
- Notch is centered at the primary display's physical top edge.
- Notch shows `XWXTodo` when no TODO is active.
- Notch shows the active TODO title when one item is doing.
- Hovering the notch replaces it with the expanded panel.
- The expanded panel hides the notch instead of appearing below it.
- Pointer exit collapses the panel back to the notch.
- Add, edit, delete, start, and complete work in the expanded panel.
- Completed items disappear from the main list.
- Completed List is read-only.
- Long titles truncate cleanly.
- The overlay remains visible over the desktop.
- The overlay remains visible over ordinary apps.
- The overlay behavior is verified over full-screen apps and separate spaces.

Packaging acceptance:

- Build a `.app`.
- Zip the `.app`.
- Unzip and launch in a clean user context or another macOS 14+ machine.
- Confirm the database is created locally on first launch.
- Confirm the app has no network dependency.

## Open Implementation Risks

- macOS may restrict overlay visibility above some full-screen apps depending on window level and collection behavior.
- Non-activating hover behavior must be verified carefully so the overlay does not steal focus from the user's current app.
- Very high window levels can create bad user experience if used carelessly; the overlay should remain small and predictable.
