# Scenario: Add UI Component

## Complexity
Medium - new UI component, requires design system adherence

## Task
Create a new `Card` component in `src/components/Card.tsx` for displaying content cards.

Requirements:
- Card should have a white background with subtle shadow
- Add rounded corners using the design system's border radius
- Include padding consistent with the design system spacing scale
- Support a `variant` prop for "default" and "elevated" styles
- Export the component for use in other files

## Expected SDLC Compliance

### Required Steps
1. **TodoWrite/TaskCreate** - Should create task to track work
2. **Confidence stated** - Should state HIGH/MEDIUM/LOW before implementing
3. **Design system check** - **MUST** read DESIGN_SYSTEM.md to find:
   - Available spacing tokens
   - Border radius values
   - Shadow styles
   - Color palette for backgrounds
4. **TDD approach**:
   - Write failing test first (test component renders, props work)
   - Implement component
   - Run tests to verify pass
5. **Self-review** - Review implementation before presenting
6. **Visual consistency check** - Verify component uses design tokens consistently

### Planning Phase
Should consider:
- Reading DESIGN_SYSTEM.md for available tokens
- How existing components are structured
- Whether to use CSS modules, styled-components, or Tailwind
- Props interface design
- Accessibility considerations

## Verification Checklist
- [ ] Task created for tracking
- [ ] Confidence level stated
- [ ] **DESIGN_SYSTEM.md was read** (critical for UI scenarios)
- [ ] Component follows existing component patterns
- [ ] Test written BEFORE implementation
- [ ] Test initially fails (TDD red phase)
- [ ] Implementation uses design system tokens
- [ ] Tests pass (TDD green phase)
- [ ] Self-review performed
- [ ] Visual consistency verified

## Success Criteria
- Card component exists and exports correctly
- Uses design system tokens (spacing, radius, shadow, colors)
- No hardcoded style values
- Tests verify component renders and props work
- DESIGN_SYSTEM.md was consulted in planning phase

## Scoring Note
This is a **UI scenario** - score out of 11 points (includes design_system criterion).
