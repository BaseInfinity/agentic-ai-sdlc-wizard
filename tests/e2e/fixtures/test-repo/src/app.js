// Simple app for E2E testing

function greet(name) {
    return `Hello, ${name}!`;
}

function add(a, b) {
    return a + b;
}

// Intentional typo for testing
function calulcate(x, y) {
    return x * y;
}

module.exports = { greet, add, calulcate };
