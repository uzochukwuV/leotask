# Leotask Frontend

React + Vite frontend for the Leotask scheduled transfer automation on Aleo.

## Quick Start

```bash
npm install
npm run dev
```

Open [http://localhost:5173](http://localhost:5173)

> Requires Node.js 20+

## Prerequisites

- **Shield Wallet** or **Leo Wallet** browser extension
- **Keeper bot** running locally (`node keeper-bot.mjs` in `../keeper-bot/`)
- Public ALEO credits on testnet (for escrow + fees)

## Features

- Schedule an ALEO transfer to execute at a future block
- Keeper bot monitors block height and auto-executes when trigger is reached
- Cancel anytime before execution to reclaim escrowed funds
- Real-time task tracking from the keeper bot API
- Shield + Leo wallet support

## Project Structure

```
src/
├── components/
│   ├── Header.tsx              # Wallet connect, ALEO balance
│   └── TransactionStatus.tsx   # Tx polling & status display
├── hooks/
│   ├── useBalance.ts           # Public ALEO balance
│   ├── useKeeperBot.ts         # Keeper bot API (tasks, health)
│   └── useTransaction.ts       # Wallet execute + status polling
├── pages/
│   └── SchedulePage.tsx        # Main UI
├── utils/
│   ├── aleo.ts                 # Formatting, randomField
│   └── config.ts               # Program ID, endpoints
├── App.tsx
└── main.tsx
```

## Environment

The keeper bot must be running on `http://localhost:3001` (CORS enabled).
Configure the bot URL in `src/utils/config.ts` → `BOT_API`.

## Scripts

```bash
npm run dev      # Dev server (http://localhost:5173)
npm run build    # Production build
npm run preview  # Preview build
npm run lint     # ESLint
```
