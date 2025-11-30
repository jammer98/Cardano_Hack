const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
require('dotenv').config();

const app = express();

// Middleware
app.use(cors({
    origin: '*',
}));
app.use(express.json());

// Simple in-memory storage (replace with MongoDB later)
let users = [];
let tenders = [];
let bids = [];

// Routes
app.post('/api/register', (req, res) => {
  const { name, email, walletAddress, role } = req.body;
  
  const existingUser = users.find(u => u.email === email);
  if (existingUser) {
    return res.status(400).json({ message: 'User already exists' });
  }
  
  const user = {
    id: Date.now().toString(),
    name,
    email,
    walletAddress,
    role, // 'government' or 'bidder'
    createdAt: new Date()
  };
  
  users.push(user);
  res.status(201).json({ message: 'User registered successfully', user });
});

app.post('/api/login', (req, res) => {
  const { email, walletAddress } = req.body;
  
  const user = users.find(u => u.email === email && u.walletAddress === walletAddress);
  if (!user) {
    return res.status(401).json({ message: 'Invalid credentials' });
  }
  
  res.json({ message: 'Login successful', user });
});

app.post('/api/tenders', (req, res) => {
  const { title, description, minBid, deadline, creatorWallet } = req.body;
  
  const tender = {
    id: Date.now().toString(),
    title,
    description,
    minBid,
    deadline,
    creatorWallet,
    status: 'active',
    bids: [],
    createdAt: new Date()
  };
  
  tenders.push(tender);
  res.status(201).json({ message: 'Tender created', tender });
});

app.get('/api/tenders', (req, res) => {
  res.json(tenders);
});

app.post('/api/bids', (req, res) => {
  const { tenderId, bidderWallet, amount, txHash } = req.body;
  
  const bid = {
    id: Date.now().toString(),
    tenderId,
    bidderWallet,
    amount,
    txHash, // Cardano transaction hash
    createdAt: new Date()
  };
  
  bids.push(bid);
  
  // Add bid to tender
  const tender = tenders.find(t => t.id === tenderId);
  if (tender) {
    tender.bids.push(bid);
  }
  
  res.status(201).json({ message: 'Bid placed', bid });
});

app.get('/api/bids/:tenderId', (req, res) => {
  const { tenderId } = req.params;
  const tenderBids = bids.filter(b => b.tenderId === tenderId);
  res.json(tenderBids);
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});