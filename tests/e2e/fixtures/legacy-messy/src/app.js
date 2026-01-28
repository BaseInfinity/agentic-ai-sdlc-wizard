// INTENTIONALLY MESSY CODE - For testing refactoring scenarios
// DO NOT use this as an example of good code!

const express = require('express');
const app = express();

app.use(express.json());

// Bad: Global mutable state
var users = [];
var items = [];
var orders = [];
var id_counter = 1;

// Bad: Function too long, does too many things
app.post('/api/register', function(req, res) {
    var email = req.body.email;
    var password = req.body.password;
    var name = req.body.name;

    // Bad: No validation abstraction
    if (!email) {
        res.status(400).json({error: 'email required'});
        return;
    }
    if (!password) {
        res.status(400).json({error: 'password required'});
        return;
    }
    if (password.length < 6) {
        res.status(400).json({error: 'password too short'});
        return;
    }

    // Bad: Linear search
    for (var i = 0; i < users.length; i++) {
        if (users[i].email == email) {
            res.status(400).json({error: 'email exists'});
            return;
        }
    }

    // Bad: Storing plain text password
    var user = {
        id: id_counter++,
        email: email,
        password: password,  // Security issue!
        name: name,
        created: new Date()
    };
    users.push(user);

    // Bad: Sending password back
    res.json(user);
});

// Bad: Copy-pasted validation logic
app.post('/api/login', function(req, res) {
    var email = req.body.email;
    var password = req.body.password;

    if (!email) {
        res.status(400).json({error: 'email required'});
        return;
    }
    if (!password) {
        res.status(400).json({error: 'password required'});
        return;
    }

    // Bad: Linear search again
    var user = null;
    for (var i = 0; i < users.length; i++) {
        if (users[i].email == email && users[i].password == password) {
            user = users[i];
            break;
        }
    }

    if (!user) {
        res.status(401).json({error: 'invalid credentials'});
        return;
    }

    // Bad: No real auth token
    res.json({token: 'fake-token-' + user.id, user: user});
});

// Bad: Callback hell potential
app.post('/api/orders', function(req, res) {
    var userId = req.body.userId;
    var itemIds = req.body.itemIds;

    // Bad: No user verification
    var user = null;
    for (var i = 0; i < users.length; i++) {
        if (users[i].id == userId) {
            user = users[i];
        }
    }

    if (!user) {
        res.status(404).json({error: 'user not found'});
        return;
    }

    // Bad: Complex nested logic
    var orderItems = [];
    var total = 0;
    for (var i = 0; i < itemIds.length; i++) {
        for (var j = 0; j < items.length; j++) {
            if (items[j].id == itemIds[i]) {
                orderItems.push(items[j]);
                total = total + items[j].price;
            }
        }
    }

    var order = {
        id: id_counter++,
        userId: userId,
        items: orderItems,
        total: total,
        status: 'pending',
        created: new Date()
    };
    orders.push(order);

    res.json(order);
});

// Bad: Magic numbers
app.get('/api/items', function(req, res) {
    var page = parseInt(req.query.page) || 1;
    var limit = 10;  // Magic number
    var start = (page - 1) * limit;
    var end = start + limit;

    var pageItems = items.slice(start, end);
    res.json({
        items: pageItems,
        total: items.length,
        page: page,
        totalPages: Math.ceil(items.length / 10)  // Duplicated magic number
    });
});

// Bad: Inconsistent naming
app.get('/api/getUserOrders', function(req, res) {
    var user_id = req.query.user_id;  // Snake case
    var userOrders = [];  // Camel case

    for (var i = 0; i < orders.length; i++) {
        if (orders[i].userId == user_id) {
            userOrders.push(orders[i]);
        }
    }

    res.json(userOrders);
});

// Bad: No error handling
app.delete('/api/items/:id', function(req, res) {
    var itemId = parseInt(req.params.id);
    var index = -1;

    for (var i = 0; i < items.length; i++) {
        if (items[i].id == itemId) {
            index = i;
        }
    }

    if (index > -1) {
        items.splice(index, 1);
    }

    res.json({success: true});  // Always returns success
});

// For testing
app.get('/api/health', (req, res) => res.json({status: 'ok'}));

// Seed data
function seedData() {
    items = [
        {id: 1, name: 'Widget', price: 9.99},
        {id: 2, name: 'Gadget', price: 19.99},
        {id: 3, name: 'Doohickey', price: 29.99}
    ];
    id_counter = 100;
}
seedData();

const PORT = process.env.PORT || 3000;
if (require.main === module) {
    app.listen(PORT, () => console.log(`Server on port ${PORT}`));
}

module.exports = { app, seedData };
