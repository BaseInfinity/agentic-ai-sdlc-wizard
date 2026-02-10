const { greet, add, calulcate, TaskManager } = require('../src/app');

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

describe('TaskManager', () => {
    let tm;

    beforeEach(() => {
        tm = new TaskManager();
    });

    describe('addTask', () => {
        it('should add a task with defaults', () => {
            const task = tm.addTask('Buy groceries');
            expect(task.id).toBe(1);
            expect(task.title).toBe('Buy groceries');
            expect(task.priority).toBe('medium');
            expect(task.completed).toBe(false);
            expect(task.tags).toEqual([]);
        });

        it('should add a task with options', () => {
            const task = tm.addTask('Deploy app', {
                priority: 'high',
                tags: ['devops'],
            });
            expect(task.priority).toBe('high');
            expect(task.tags).toEqual(['devops']);
        });

        it('should throw on empty title', () => {
            expect(() => tm.addTask('')).toThrow('Task title is required');
        });

        it('should auto-increment ids', () => {
            const t1 = tm.addTask('First');
            const t2 = tm.addTask('Second');
            expect(t2.id).toBe(t1.id + 1);
        });
    });

    describe('completeTask', () => {
        it('should mark a task as completed', () => {
            const task = tm.addTask('Test task');
            const completed = tm.completeTask(task.id);
            expect(completed.completed).toBe(true);
            expect(completed.completedAt).toBeTruthy();
        });

        it('should throw if task not found', () => {
            expect(() => tm.completeTask(999)).toThrow('Task 999 not found');
        });

        it('should throw if already completed', () => {
            const task = tm.addTask('Test task');
            tm.completeTask(task.id);
            expect(() => tm.completeTask(task.id)).toThrow('already completed');
        });
    });

    describe('listTasks', () => {
        it('should list all tasks', () => {
            tm.addTask('A');
            tm.addTask('B');
            expect(tm.listTasks()).toHaveLength(2);
        });

        it('should filter by completed status', () => {
            tm.addTask('Done');
            tm.addTask('Pending');
            tm.completeTask(1);
            expect(tm.listTasks({ completed: true })).toHaveLength(1);
            expect(tm.listTasks({ completed: false })).toHaveLength(1);
        });

        it('should filter by priority', () => {
            tm.addTask('Low task', { priority: 'low' });
            tm.addTask('High task', { priority: 'high' });
            expect(tm.listTasks({ priority: 'high' })).toHaveLength(1);
        });
    });

    describe('filterByTag', () => {
        it('should return tasks with matching tag', () => {
            tm.addTask('Tagged', { tags: ['urgent'] });
            tm.addTask('Not tagged');
            expect(tm.filterByTag('urgent')).toHaveLength(1);
        });
    });

    // Note: searchTasks and calulcateStats have limited test coverage
    // Scenarios may ask to expand tests here (TDD opportunity)
});
