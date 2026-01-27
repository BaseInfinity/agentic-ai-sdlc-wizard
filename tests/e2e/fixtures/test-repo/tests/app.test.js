// Test file for E2E testing

const { greet, add, calulcate } = require('../src/app');

describe('greet', () => {
    it('should greet by name', () => {
        expect(greet('World')).toBe('Hello, World!');
    });
});

describe('add', () => {
    it('should add two numbers', () => {
        expect(add(2, 3)).toBe(5);
    });
});

// Note: calulcate is misspelled - test scenario will fix this
describe('calulcate', () => {
    it('should multiply two numbers', () => {
        expect(calulcate(2, 3)).toBe(6);
    });
});
