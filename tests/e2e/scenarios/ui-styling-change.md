# Scenario: UI Styling Change

## Complexity
Medium - involves UI/CSS changes, requires design system check

## Task
Update the button styles in `src/components/Button.tsx` to use the design system colors.

Requirements:
- Change the primary button background to use the design system's `primary-500` color
- Change the button text to use the design system's `neutral-50` color
- Ensure hover state uses `primary-600`
- Do not use hardcoded hex values - use CSS variables or design tokens

## Expected SDLC Compliance

### Required Steps
1. **TodoWrite/TaskCreate** - Should create task to track work
2. **Confidence stated** - Should state HIGH/MEDIUM/LOW before implementing
3. **Design system check** - **MUST** read DESIGN_SYSTEM.md to find correct tokens
4. **TDD approach**:
   - Write failing test first (test for correct CSS classes/styles)
   - Implement style changes
   - Run tests to verify pass
5. **Self-review** - Review implementation before presenting
6. **Visual consistency check** - Verify colors match design system palette

### Planning Phase
Should consider:
- Reading DESIGN_SYSTEM.md to understand available tokens
- What CSS variables or design tokens are available
- How existing components use the design system
- Whether the change affects other components

## Verification Checklist
- [ ] Task created for tracking
- [ ] Confidence level stated
- [ ] **DESIGN_SYSTEM.md was read** (critical for UI scenarios)
- [ ] Test written BEFORE implementation
- [ ] Test initially fails (TDD red phase)
- [ ] Implementation uses design system tokens (not hardcoded values)
- [ ] Tests pass (TDD green phase)
- [ ] Self-review performed
- [ ] Visual consistency verified (colors from palette)

## Success Criteria
- Button uses design system color tokens
- No hardcoded color values (no `#RRGGBB` or `rgb()`)
- Tests verify correct styling classes applied
- DESIGN_SYSTEM.md was consulted in planning phase

## Scoring Note
This is a **UI scenario** - score out of 11 points (includes design_system criterion).
