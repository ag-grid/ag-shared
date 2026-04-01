# AG Grid — JIRA Product Configuration

## Identity

- **Project**: `AG`
- **Component**: `Grid`
- **Summary prefix**: `[Grid]`

## API Field Values

```json
{
    "projectKey": "AG",
    "components": [{ "name": "Grid" }],
    "summary": "[Grid] ..."
}
```

## Version Relationship

Grid is the reference version. Charts major version = Grid major version - 22.

## Task Structure Conventions

When a larger requirement needs subtasks, follow this pattern:

1. Add a single top-level task for the feature request and create subtasks:
    - **Non-functional requirements subtasks:**
        - Conceptual UX and UI design.
        - Production of design assets.
        - Localization.
        - Accessibility.
        - Theming.
    - **Functional requirements subtasks:** Different functional areas or materially different configurations where the new feature will work.

2. Each subtask must be self-contained. The top-level task contains an overview and shows the overall structure of subtasks.

3. Only include subtasks which are in scope for the initial release. Subtasks not part of the initial release are moved to a separate containing task for later implementation.

4. Re-link ZenDesk tickets to the relevant subtasks so they can easily be accessed within the context of each subtask.

### Task Assignment

- The top-level task is assigned to the Product Manager who owns it.
- UX Design and Design Production subtasks are assigned to the UX Designer.
- Development implementation subtasks are assigned to the developer involved.

### Title Format

- Precede the title with `[Feature Name]` to indicate its feature area.
- New end-user features: `"Allow <user action> when <relevant grid configuration>"`.
- New API features: `"Add support for <desired behavior> when using <existing grid feature>"`.

### Reference Example

See [AG-7954](https://ag-grid.atlassian.net/browse/AG-7954) for an example task following this format.

## Estimation Calibration Data

TBD — to be populated by the Grid team.
