import { render } from '@testing-library/react';
import { describe, it, expect } from 'vitest';

// Minimal smoke test — verifies the test harness works before Phase 1 adds real components
describe('test harness', () => {
  it('renders a div without errors', () => {
    const { container } = render(<div data-testid="smoke">ok</div>);
    expect(container.querySelector('[data-testid="smoke"]')).toBeTruthy();
  });
});
