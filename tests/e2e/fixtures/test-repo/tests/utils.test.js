const { formatDate, slugify, truncate, deepClone } = require('../src/utils');

describe('formatDate', () => {
    it('should format ISO date string', () => {
        expect(formatDate('2025-06-15T10:30:00.000Z')).toBe('2025-06-15');
    });

    it('should return N/A for null', () => {
        expect(formatDate(null)).toBe('N/A');
    });

    it('should return Invalid Date for bad input', () => {
        expect(formatDate('not-a-date')).toBe('Invalid Date');
    });
});

describe('slugify', () => {
    it('should slugify a simple string', () => {
        expect(slugify('Hello World')).toBe('hello-world');
    });

    it('should remove special characters', () => {
        expect(slugify('Buy groceries!')).toBe('buy-groceries');
    });

    it('should trim whitespace', () => {
        expect(slugify('  spaced out  ')).toBe('spaced-out');
    });
});

describe('truncate', () => {
    it('should not truncate short strings', () => {
        expect(truncate('hello', 10)).toBe('hello');
    });

    it('should truncate long strings with ellipsis', () => {
        expect(truncate('a very long string here', 10)).toBe('a very ...');
    });
});

describe('deepClone', () => {
    it('should clone nested objects', () => {
        const obj = { a: { b: [1, 2] } };
        const cloned = deepClone(obj);
        expect(cloned).toEqual(obj);
        cloned.a.b.push(3);
        expect(obj.a.b).toHaveLength(2);
    });

    it('should handle null', () => {
        expect(deepClone(null)).toBeNull();
    });
});
