// Task Manager - E2E test fixture
// Provides enough complexity for meaningful SDLC simulations

const { formatDate, slugify, deepClone } = require('./utils');

// Legacy function names kept for scenario backward compatibility
function greet(name) {
    return `Hello, ${name}!`;
}

function add(a, b) {
    return a + b;
}

// Intentional typo for testing (scenarios reference this)
function calulcate(x, y) {
    return x * y;
}

class TaskManager {
    constructor() {
        this.tasks = [];
        this.nextId = 1;
    }

    addTask(title, { priority = 'medium', tags = [], dueDate = null } = {}) {
        if (!title || typeof title !== 'string') {
            throw new Error('Task title is required and must be a string');
        }

        const task = {
            id: this.nextId++,
            title: title.trim(),
            slug: slugify(title),
            priority,
            tags: [...tags],
            completed: false,
            createdAt: new Date().toISOString(),
            dueDate,
            completedAt: null,
        };

        this.tasks.push(task);
        return task;
    }

    completeTask(id) {
        const task = this.tasks.find(t => t.id === id);
        if (!task) {
            throw new Error(`Task ${id} not found`);
        }
        if (task.completed) {
            throw new Error(`Task ${id} is already completed`);
        }
        task.completed = true;
        task.completedAt = new Date().toISOString();
        return task;
    }

    listTasks({ completed = null, priority = null } = {}) {
        let result = deepClone(this.tasks);

        if (completed !== null) {
            result = result.filter(t => t.completed === completed);
        }
        if (priority !== null) {
            result = result.filter(t => t.priority === priority);
        }

        return result;
    }

    filterByTag(tag) {
        return this.tasks.filter(t => t.tags.includes(tag));
    }

    searchTasks(query) {
        const lower = query.toLowerCase();
        return this.tasks.filter(t =>
            t.title.toLowerCase().includes(lower) ||
            t.tags.some(tag => tag.toLowerCase().includes(lower))
        );
    }

    // Intentional typo: calulcateStats instead of calculateStats
    // Scenarios may ask to fix this
    calulcateStats() {
        const total = this.tasks.length;
        const completed = this.tasks.filter(t => t.completed).length;
        const pending = total - completed;

        // Bug: floating-point priority sorting uses string comparison
        // This causes '10' < '9' when sorting by priority weight
        const priorityWeights = { high: 3, medium: 2, low: 1 };
        const avgPriority = total > 0
            ? this.tasks.reduce((sum, t) => sum + (priorityWeights[t.priority] || 0), 0) / total
            : 0;

        return {
            total,
            completed,
            pending,
            completionRate: total > 0 ? Math.round((completed / total) * 100) : 0,
            avgPriority: Math.round(avgPriority * 100) / 100,
        };
    }

    getOverdueTasks() {
        const now = new Date();
        return this.tasks.filter(t =>
            !t.completed && t.dueDate && new Date(t.dueDate) < now
        );
    }
}

module.exports = { greet, add, calulcate, TaskManager };
