# Aleo Football Manager - Final Architecture

## Core Concept: Stats = Win Probability

**Team A (80 attack) vs Team B (60 attack)**
- A win chance: 80 / (80+60) = 57%
- Roll dice → winner based on probability

---

## Data Structures

```leo
// TEAM RECORD - Private state, owned by user
record Team {
    owner: address,
    name: field,
    
    // Team Stats
    attack: u8,     // 0-100
    defense: u8,    // 0-100
    midfield: u8,   // 0-100
    speed: u8,      // 0-100
    
    // Experience - increases with games
    xp: u32,
    
    // PUBLIC - opponent can see
    formation: u8,  // 0=4-4-2, 1=4-3-3, 2=3-5-2
    
    // PRIVATE - hidden from opponent!
    aggression: u8,   // 0=Caution, 1=Normal, 2=Aggressive, 3=AllOut
    pressing: u8,    // 0=Low, 1=Medium, 2=High, 3=FullCourt
    morale: u8,      // 0=Low, 1=Normal, 2=High, 3=Euphoric
    strategy: u8,    // 0=RouteOne, 1=TikiTaka, 2=Counter, 3=Parking
    
    // Record
    wins: u32,
    losses: u32,
    draws: u32,
    elo: u32,
    nonce: u64,
}

// MATCH RESULT - Public
struct MatchResult {
    match_id: u64,
    home_team_id: field,
    away_team_id: field,
    
    // The drama!
    first_half: HalfScore,
    second_half: HalfScore,
    
    home_goals: u8,
    away_goals: u8,
    winner: address,
    
    // For verification
    home_power: u16,
    away_power: u16,
}

struct HalfScore {
    home: u8,
    away: u8,
}
```

---

## Core Flow

```
Create Team → Set Tactics (private!) → Request Match → 
Play First Half → Play Second Half → 
Update XP/ELO → View League Rankings
```

---

## Key Functions

### 1. Create Team
```leo
transition create_team(
    name: field,
    formation: u8,
    seed: field
) -> Team
```

### 2. Update Tactics (Private!)
```leo
transition set_tactics(
    team: Team,
    aggression: u8,
    pressing: u8,
    morale: u8,
    strategy: u8
) -> Team
```

### 3. Play Match
```leo
transition play_match(
    home_team: Team,
    away_team: Team,
    seed: field
) -> (Team, Team, MatchResult)
```

---

## Match Logic

### Calculate Power
```leo
inline calc_power(team: Team) -> u16 {
    let base: u16 = (team.attack as u16 + team.defense as u16 + 
                     team.midfield as u16 + team.speed as u16) * 4u16;
    
    // Morale bonus (0-15%)
    let morale_bonus: u16 = (team.morale as u16 * 5u16);
    
    // Strategy multiplier
    let strat_mult: u16 = match team.strategy {
        0u8 => 105u16,  // RouteOne - balanced
        1u8 => 100u16,  // TikiTaka - possession
        2u8 => 110u16,  // Counter - defense
        3u8 => 95u16,   // Parking - ultra-defense
    };
    
    base * (100u16 + morale_bonus) / 100u16 * strat_mult / 100u16
}
```

### Simulate Half
```leo
function simulate_half(
    home_power: u16,
    away_power: u16,
    home_aggression: u8,
    away_aggression: u8,
    seed: field
) -> (u8, u8) {
    // Win probability based on power
    let total: u16 = home_power + away_power;
    let home_prob: u8 = (home_power * 100u16 / total) as u8;
    
    let roll: u8 = random(seed) % 100u8;
    
    if roll < home_prob {
        // Home wins half - aggression affects goals
        let goals: u8 = 1u8 + (home_aggression / 2u8);  // 1-2 goals
        return (goals, 0u8);
    } else if roll < home_prob + 20u8 {
        // Draw
        return (0u8, 0u8);
    } else {
        // Away wins half
        let goals: u8 = 1u8 + (away_aggression / 2u8);
        return (0u8, goals);
    }
}
```

---

## Privacy Design

| Data | Visibility | Why |
|------|------------|-----|
| Team stats (attack, defense...) | Private | Hide strength |
| Tactics (aggression, pressing...) | **PRIVATE** | Surprise opponent! |
| Morale | Private | Hidden advantage |
| Formation | **PUBLIC** | Fair - both see |
| Match result | Public | Verifiable |
| ELO/Rankings | Public | Leaderboard |

---

## XP System

```leo
// XP earned per match
inline calc_xp(played: bool, won: bool, draw: bool) -> u32 {
    let base: u32 = 10u32;   // Participated
    if won { base + 50u32 }
    else if draw { base + 20u32 }
    else { base }
}

// Level from XP
inline calc_level(xp: u32) -> u8 {
    // Every 100 XP = 1 level
    (xp / 100u32) as u8
}
```

---

## Implementation Priority

1. **Team creation** - Basic team with random stats
2. **Set tactics** - Update the 4 private settings
3. **Match simulation** - First half + second half
4. **ELO system** - Rankings
5. **Find match** - Matchmaking

### 1. Simplified Data Structures

### Auto-Generated Team (No Minting!)

```leo
// Simple team - 11 players auto-generated when team is created
record Team {
    owner: address,
    name: field,
    players: [Player; 11],      // Auto-generated on team creation
    tactic: u8,                 // 0=ATTACK, 1=BALANCED, 2=DEFENSE
    wins: u32,
    losses: u32,
    draws: u32,
    elo: u32,
    nonce: u64,
}

struct Player {
    attack: u8,
    defense: u8,
    midfield: u8,
    speed: u8,
}

// Each player has 4 stats (0-100)
// Team total = sum of all 11 players' stats = ~2200 max
```

### Match State

```leo
// Half scores for first half / second half display
struct HalfScore {
    home: u8,
    away: u8,
}

struct MatchResult {
    match_id: u64,
    home_team_id: field,
    away_team_id: field,
    
    // The drama!
    first_half: HalfScore,
    second_half: HalfScore,
    
    // Final
    home_goals: u8,      // first_half.home + second_half.home
    away_goals: u8,      // first_half.away + second_half.away
    
    // Winner
    winner: address,     // zero address if draw
    
    // For XP calculation
    home_stat_power: u16,
    away_stat_power: u16,
}

// Public mapping for match results (verifiable)
mapping match_results: u64 => MatchResult;

// Private - team record for owner
mapping teams: field => Team;
mapping team_counter: bool => u64;
```
```

---

## 2. Core Flow

### The Flow: Create Team → Find Match → Play → League

```
┌──────────────┐     ┌────────────────┐     ┌─────────────┐
│ 1. Create    │────▶│ 2. Find Match  │────▶│ 3. Play     │
│    Team       │     │    (random)    │     │    Match    │
└──────────────┘     └────────────────┘     └──────┬──────┘
                                                   │
                    ┌────────────────┐              │
                    │ 5. League      │◀─────────────┘
                    │ Rankings       │
                    └────────────────┘
                         ▲
                         │
                    ┌────┴──────┐
                    │ 4. Earn   │
                    │ XP/ELO    │
                    └───────────┘
```

### Module 1: Team Creation

```leo
// Create a team with auto-generated players
transition create_team(
    name: field,
    tactic: u8,  // 0=ATTACK, 1=BALANCED, 2=DEFENSE
    seed: field
) -> Team {
    // Auto-generate 11 players with random stats
    let players: [Player; 11] = generate_players(seed);
    
    let team_id: field = BHP256::hash_to_field(self.caller as field + seed);
    
    return Team {
        owner: self.caller,
        name,
        players,
        tactic,
        wins: 0u32,
        losses: 0u32,
        draws: 0u32,
        elo: 1000u32,  // Starting ELO
        nonce: 0u64,
    };
}

// Generate 11 players with random stats (called internally)
function generate_players(seed: field) -> [Player; 11] {
    let mut players: [Player; 11] = empty();
    
    for i in 0u32..11u32 {
        let player_seed: field = seed + (i as field);
        // Each stat 40-80 (some randomness)
        let attack: u8 = 40u8 + (hash_to_u8(player_seed, 100u32) % 40u8);
        let defense: u8 = 40u8 + (hash_to_u8(player_seed + 1field, 100u32) % 40u8);
        let midfield: u8 = 40u8 + (hash_to_u8(player_seed + 2field, 100u32) % 40u8);
        let speed: u8 = 40u8 + (hash_to_u8(player_seed + 3field, 100u32) % 40u8);
        
        players[i as usize] = Player { attack, defense, midfield, speed };
    }
    
    players
}
```

### Module 2: Match Request

```leo
// Request a random match against another team
transition request_match(
    home_team: Team
) -> Future {
    // Find any waiting team from mapping
    // Or add to waiting queue
    return finalize_match_request(home_team.owner, home_team.team_id);
}

async function finalize_match_request(
    requester: address,
    team_id: field
) {
    // Check if there's a team waiting
    // If yes, create match
    // If no, add to waiting queue
}
```

### Module 3: Play Match (THE CORE!)

```leo
transition play_match(
    home_team: Team,
    away_team: Team,
    seed: field
) -> (Team, Team, MatchResult) {
    // Calculate team power
    let home_power: u16 = calculate_team_power(home_team);
    let away_power: u16 = calculate_team_power(away_team);
    
    // Calculate win probabilities
    let total_power: u16 = home_power + away_power;
    let home_win_prob: u8 = (home_power * 100u16 / total_power) as u8;  // 0-100
    
    // FIRST HALF
    let (h1, a1): (u8, u8) = simulate_half(home_power, away_power, home_win_prob, seed);
    
    // SECOND HALF
    let (h2, a2): (u8, u8) = simulate_half(home_power, away_power, home_win_prob, seed + 100field);
    
    // Final score
    let home_goals: u8 = h1 + h2;
    let away_goals: u8 = a1 + a2;
    
    // Determine winner
    let winner: address = if home_goals > away_goals { home_team.owner }
        else if away_goals > home_goals { away_team.owner }
        else { zero_address };
    
    // Update records
    let new_home: Team = update_stats(home_team, home_goals, away_goals);
    let new_away: Team = update_stats(away_team, away_goals, home_goals);
    
    let result: MatchResult = MatchResult {
        match_id: 0u64,
        home_team_id: 0field,
        away_team_id: 0field,
        first_half: HalfScore { home: h1, away: a1 },
        second_half: HalfScore { home: h2, away: a2 },
        home_goals,
        away_goals,
        winner,
        home_stat_power: home_power,
        away_stat_power: away_power,
    };
    
    return (new_home, new_away, result);
}
```

### Module 4: League Rankings

```leo
// Simple ELO system
inline calculate_elo_change(
    winner_elo: u32,
    loser_elo: u32
) -> (u32, u32) {
    // Winner gains more if they were underdog
    let expected: u32 = 1u32 + (loser_elo - winner_elo) / 10u32;
    let winner_gain: u32 = 20u32 + expected;
    let loser_loss: u32 = 20u32 + expected;
    
    (winner_gain, loser_loss)
}

// Update league table
mapping league: u32 => address_elo;  // rank -> (address, elo)
mapping player_elo: address => u32;

---

## 3. Game Mechanics

### Match Simulation Algorithm

```leo
// Line Power Calculation
inline calculate_line_power(team: TeamRecord, is_attacking: bool) -> u16 {
    let mut power: u16 = 0u16;
    
    if is_attacking {
        // Sum attack + midfield + speed of forwards + midfielders
        for i in 4u32..11u32 {  // forward + midfield positions
            power += team.players[i as usize].attack as u16;
            power += team.players[i as usize].midfield as u16;
        }
    } else {
        // Sum defense + goalkeeper
        power += team.players[0].defense as u16;  // goalkeeper
        for i in 1u32..5u32 {  // defenders
            power += team.players[i as usize].defense as u16;
        }
    }
    
    // Tactic modifier
    let tactic_bonus: u16 = match team.tactic {
        ATTACKING => 120u16,
        BALANCED => 100u16,
        DEFENSIVE => 80u16,
        _ => 100u16,
    };
    
    power * tactic_bonus / 100u16
}

// Stamina penalty
inline stamina_penalty(stamina: u8) -> u16 {
    if stamina > 80u8 { 100u16 }
    else if stamina > 50u8 { 80u16 }
    else { 50u16 }
}
```

### XP System

```leo
inline calculate_xp(
    played: bool,
    won: bool,
    goals_scored: u8,
    clutch_moment: bool
) -> u32 {
    let mut xp: u32 = 10u32;  // Base XP for playing
    
    if won { xp += 50u32; }
    xp += (goals_scored as u32) * 10u32;
    if clutch_moment { xp += 25u32; }
    
    xp
}
```

### Player Generation (Rarity)

```leo
function generate_player(rarity: u8, seed: field) -> Player {
    let base_stats: u8 = match rarity {
        1u8 => 40u8,   // Common
        2u8 => 55u8,   // Rare  
        3u8 => 70u8,   // Epic
        4u8 => 85u8,   // Legendary
    };
    
    // Randomize around base
    let attack: u8 = base_stats + (rng(seed, 100u32) % 20u32) as u8;
    let defense: u8 = base_stats + (rng(seed + 1field, 100u32) % 20u32) as u8;
    let midfield: u8 = base_stats + (rng(seed + 2field, 100u32) % 20u32) as u8;
    let speed: u8 = base_stats + (rng(seed + 3field, 100u32) % 20u32) as u8;
    let clutch: u8 = base_stats / 2u8 + (rng(seed + 4field, 50u32) % 10u32) as u8;
    
    Player {
        pos:  /* based on seed */,
        attack,
        defense,
        midfield,
        speed,
        stamina: 100u8,
        xp: 0u32,
        clutch,
    }
}
```

---

## 4. Privacy Design

| Data | Type | Visibility |
|------|------|------------|
| Team lineup | `record` | **Private** - opponent doesn't see |
| Player stats | `record` | **Private** - hidden until match |
| Stamina | `record` | **Private** - no stamina hunting |
| Tactics | `record` | **Private** - surprise opponent |
| Match result | `mapping` | **Public** - fair verification |
| Tournament bracket | `mapping` | **Public** - verifiable |
| ELO rankings | `mapping` | **Public** - leaderboard |

---

## 5. Economic Model

### Revenue Streams
1. **Player minting** - Cost ALEO to mint players
2. **Packs** - Buy player packs
3. **Tournament entry** - Entry fees
4. **Rest & Recovery** - Stamina regeneration (shown in V5!)
5. **Stadium upgrades** - Improve home advantage

### Stamina Economics (from V5)
```leo
let base_cost: u64 = 500_000u64;      // 0.5 ALEO
let per_tired_cost: u64 = 50_000u64;  // +0.05 ALEO per player < 50 stamina
```

---

## 6. Implementation Order

### Phase 1: Core
1. [ ] Define all enums and structs
2. [ ] Team creation
3. [ ] Player minting
4. [ ] Basic match simulation

### Phase 2: Gameplay
5. [ ] Rest & Recovery (already in V5!)
6. [ ] Tournament system
7. [ ] XP system
8. [ ] Penalty shootout

### Phase 3: Economy
9. [ ] Player packs
10. [ ] Stadium upgrades
11. [ ] League/ELO

### Phase 4: Polish
12. [ ] Frontend
13. [ ] Testing
14. [ ] Mainnet deployment

---

## 7. Key Code Gaps to Fill

The provided V5 code has these needs:

1. **Enums** - Position, Formation, Tactic definitions
2. **`calculate_line_power`** function implementation
3. **`update_team_stats`** function implementation  
4. **`apply_clutch`** function implementation
5. **`rng`** function (random number generation)
6. **Team creation** transition
7. **Player minting** transitions
8. **Tournament management** transitions
9. **Mappings** for storing teams, matches, tournaments

---

## Summary

This Football Manager combines:
- ✅ Privacy (private team data)
- ✅ Economic depth (minting, stamina recovery)
- ✅ Competitive integrity (public match results)
- ✅ Addictive gameplay (XP, tournaments, ELO)

The V5 Rest & Recovery mechanic is brilliant - it creates real economic value while being perfectly integrated into gameplay!

Ready to start implementation?
