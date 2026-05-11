# Legitimate Step Fixture Spec — Step under non-Phase parent (allowed)

## Coding Specification for Implementation

## Phase 1: Real Phase

### Change 1: A real Change

**Problem:** trivial.

**File:** noop.

## gate fast

### Step 1: This is allowed — parent is "gate fast", not "Phase"

A workflow-runner description like the kermit-harness gate steps is allowed
to use "Step N" because the parent header is NOT a Phase. The taxonomy
checker has an explicit carve-out for this case.

### Step 2: Also allowed for the same reason

noop.
