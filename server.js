const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());
app.use(express.static('public')); // Frontend fayllari uchun

let reports = [];
let adminChat = [];
let pendingCommands = [];
let stats = { daily: 0, weekly: { "Du": 0, "Se": 0, "Ch": 0, "Pa": 0, "Ju": 0, "Sh": 0, "Ya": 0 } };

// API Endpoints
app.post('/api/send-report', (req, res) => {
    const { text } = req.body;
    const match = text.match(/(?:Report|#)(\d+)/i) || text.match(/(\d+)/);
    const id = match ? match[1] : Date.now();

    reports.unshift({ id, text, time: new Date().toLocaleTimeString() });
    res.json({ status: 'ok' });
});

app.post('/api/send-chat', (req, res) => {
    adminChat.unshift({ text: req.body.text, time: new Date().toLocaleTimeString() });
    res.json({ status: 'ok' });
});

app.get('/api/data', (req, res) => {
    res.json({ reports, adminChat, stats });
});

app.post('/api/execute', (req, res) => {
    const { command } = req.body;
    pendingCommands.push(command);
    if (command.startsWith('/ans')) stats.daily++;
    res.json({ status: 'queued' });
});

app.get('/api/get-commands', (req, res) => {
    res.json(pendingCommands);
    pendingCommands = [];
});

app.listen(3000, () => console.log('🚀 Web Admin Panel serveri 3000-portda ishga tushdi!'));