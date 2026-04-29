# Sim Baseline — Pre-CombatState Refactor

Captured 2026-04-25, 200 runs per combination, full Act 1 + Act 2 matrix.
Used as the regression reference for Phases 1–5 of the CombatState extraction.
Each phase must reproduce these win-rate / HP / champion numbers within sim noise (~±2pp on 200 runs).

```
=== Echo of Abyss — Batch Balance Simulator ===
Runs per combination: 200
Acts: [1, 2]

--- Act 1 ---
Swarm      | none | F1 Rogue Imp Pack         | Win  59.0% | Loss  41.0% | T  6.0 | HP +1158 | Champ 0.54 [f1_a]
Swarm      | none | F1 Rogue Imp Pack         | Win  68.0% | Loss  32.0% | T  5.9 | HP +1604 | Champ 0.59 [f1_b]
Swarm      | none | F1 Rogue Imp Pack         | Win  51.5% | Loss  48.5% | T  6.1 | HP +1151 | Champ 0.55 [f1_c]
Swarm      | none | F2 Corrupted Broodlings   | Win  84.0% | Loss  16.0% | T  6.1 | HP +1922 | Champ 0.68 [f2_a]
Swarm      | none | F2 Corrupted Broodlings   | Win  81.5% | Loss  18.5% | T  5.4 | HP +1518 | Champ 0.46 [f2_b]
Swarm      | none | F2 Corrupted Broodlings   | Win  90.0% | Loss  10.0% | T  5.5 | HP +1979 | Champ 0.31 [f2_c]
Swarm      | none | F3 Imp Matriarch          | Win  85.5% | Loss  14.5% | T  5.8 | HP +2022 | Champ 0.09 [f3_a]
Swarm      | none | F3 Imp Matriarch          | Win  79.5% | Loss  20.5% | T  7.5 | HP +2249 | Champ 0.19 [f3_b]
Swarm      | none | F3 Imp Matriarch          | Win  78.0% | Loss  22.0% | T  6.4 | HP +2249 | Champ 0.16 [f3_c]
Voidbolt   | none | F1 Rogue Imp Pack         | Win  84.5% | Loss  15.5% | T  5.8 | HP +1316 | Champ 0.24 [f1_a]
             Plg:1.2/1.1 | VB:1.3x/1776dmg | Imp:244
Voidbolt   | none | F1 Rogue Imp Pack         | Win  82.5% | Loss  17.5% | T  5.8 | HP +1551 | Champ 0.32 [f1_b]
             Plg:1.2/1.4 | VB:1.4x/1795dmg | Imp:250
Voidbolt   | none | F1 Rogue Imp Pack         | Win  77.5% | Loss  22.5% | T  5.8 | HP +1458 | Champ 0.17 [f1_c]
             Plg:1.3/1.2 | VB:1.3x/1749dmg | Imp:254
Voidbolt   | none | F2 Corrupted Broodlings   | Win  86.0% | Loss  14.0% | T  6.0 | HP +1325 | Champ 0.50 [f2_a]
             Plg:1.3/0.2 | VB:1.3x/1870dmg | Imp:262
Voidbolt   | none | F2 Corrupted Broodlings   | Win  79.5% | Loss  20.5% | T  5.9 | HP +1003 | Champ 0.45 [f2_b]
             Plg:1.3/0.1 | VB:1.4x/1841dmg | Imp:261
Voidbolt   | none | F2 Corrupted Broodlings   | Win  88.5% | Loss  11.5% | T  5.7 | HP +1556 | Champ 0.30 [f2_c]
             Plg:1.2/0.1 | VB:1.3x/1766dmg | Imp:263
Voidbolt   | none | F3 Imp Matriarch          | Win  65.5% | Loss  34.5% | T  5.9 | HP +1112 | Champ 0.17 [f3_a]
             Plg:1.2/0.2 | VB:1.4x/1919dmg | Imp:262
Voidbolt   | none | F3 Imp Matriarch          | Win  75.5% | Loss  24.5% | T  7.2 | HP +1485 | Champ 0.28 [f3_b]
             Plg:1.5/0.8 | VB:1.7x/2732dmg | Imp:316
Voidbolt   | none | F3 Imp Matriarch          | Win  66.5% | Loss  33.5% | T  6.9 | HP +1367 | Champ 0.24 [f3_c]
             Plg:1.4/1.2 | VB:1.6x/2474dmg | Imp:309
DeathCircle | none | F1 Rogue Imp Pack         | Win  51.5% | Loss  48.5% | T  6.1 | HP  +923 | Champ 0.62 [f1_a]
             PRit:1.1
DeathCircle | none | F1 Rogue Imp Pack         | Win  70.0% | Loss  30.0% | T  6.1 | HP +1647 | Champ 0.51 [f1_b]
             PRit:1.2
DeathCircle | none | F1 Rogue Imp Pack         | Win  52.5% | Loss  47.5% | T  5.9 | HP +1182 | Champ 0.47 [f1_c]
             PRit:1.0
DeathCircle | none | F2 Corrupted Broodlings   | Win  85.0% | Loss  15.0% | T  5.9 | HP +1911 | Champ 0.69 [f2_a]
             PRit:1.1
DeathCircle | none | F2 Corrupted Broodlings   | Win  65.5% | Loss  34.5% | T  5.4 | HP +1309 | Champ 0.53 [f2_b]
             PRit:0.9
DeathCircle | none | F2 Corrupted Broodlings   | Win  81.5% | Loss  18.5% | T  5.8 | HP +1798 | Champ 0.48 [f2_c]
             PRit:0.9
DeathCircle | none | F3 Imp Matriarch          | Win  70.0% | Loss  30.0% | T  6.0 | HP +1588 | Champ 0.17 [f3_a]
             PRit:1.0
DeathCircle | none | F3 Imp Matriarch          | Win  59.0% | Loss  41.0% | T  8.3 | HP +1560 | Champ 0.38 [f3_b]
             PRit:1.4
DeathCircle | none | F3 Imp Matriarch          | Win  62.5% | Loss  37.5% | T  7.6 | HP +1637 | Champ 0.32 [f3_c]
             PRit:1.4
S.Flesh    | none | F1 Rogue Imp Pack         | Win  71.5% | Loss  28.5% | T  6.1 | HP +1365 | Champ 0.50 [f1_a]
S.Flesh    | none | F1 Rogue Imp Pack         | Win  79.5% | Loss  20.5% | T  6.0 | HP +1895 | Champ 0.59 [f1_b]
S.Flesh    | none | F1 Rogue Imp Pack         | Win  59.5% | Loss  40.5% | T  6.1 | HP +1436 | Champ 0.51 [f1_c]
S.Flesh    | none | F2 Corrupted Broodlings   | Win  51.0% | Loss  49.0% | T  6.8 | HP  +972 | Champ 0.68 [f2_a]
S.Flesh    | none | F2 Corrupted Broodlings   | Win  37.0% | Loss  63.0% | T  6.1 | HP  +524 | Champ 0.50 [f2_b]
S.Flesh    | none | F2 Corrupted Broodlings   | Win  65.5% | Loss  34.5% | T  6.0 | HP +1267 | Champ 0.31 [f2_c]
S.Flesh    | none | F3 Imp Matriarch          | Win  64.5% | Loss  35.5% | T  6.3 | HP +1292 | Champ 0.16 [f3_a]
S.Flesh    | none | F3 Imp Matriarch          | Win  65.5% | Loss  34.5% | T  7.7 | HP +1791 | Champ 0.28 [f3_b]
S.Flesh    | none | F3 Imp Matriarch          | Win  86.5% | Loss  13.5% | T  6.1 | HP +2431 | Champ 0.11 [f3_c]
S.Forge    | none | F1 Rogue Imp Pack         | Win  20.0% | Loss  80.0% | T  5.3 | HP   +77 | Champ 0.45 [f1_a]
S.Forge    | none | F1 Rogue Imp Pack         | Win  26.0% | Loss  74.0% | T  5.3 | HP  +345 | Champ 0.56 [f1_b]
S.Forge    | none | F1 Rogue Imp Pack         | Win  15.0% | Loss  85.0% | T  5.4 | HP   +62 | Champ 0.46 [f1_c]
S.Forge    | none | F2 Corrupted Broodlings   | Win  52.5% | Loss  47.5% | T  7.0 | HP  +758 | Champ 0.69 [f2_a]
S.Forge    | none | F2 Corrupted Broodlings   | Win  24.5% | Loss  75.5% | T  5.6 | HP  +264 | Champ 0.25 [f2_b]
S.Forge    | none | F2 Corrupted Broodlings   | Win  43.5% | Loss  56.5% | T  6.3 | HP  +660 | Champ 0.32 [f2_c]
S.Forge    | none | F3 Imp Matriarch          | Win  25.0% | Loss  75.0% | T  6.7 | HP  +150 | Champ 0.23 [f3_a]
S.Forge    | none | F3 Imp Matriarch          | Win  35.5% | Loss  64.5% | T  8.6 | HP  +580 | Champ 0.41 [f3_b]
S.Forge    | none | F3 Imp Matriarch          | Win  40.0% | Loss  60.0% | T  7.3 | HP  +778 | Champ 0.34 [f3_c]
S.Corr     | none | F1 Rogue Imp Pack         | Win  15.0% | Loss  85.0% | T  4.9 | HP   +40 | Champ 0.46 [f1_a]
S.Corr     | none | F1 Rogue Imp Pack         | Win  28.0% | Loss  72.0% | T  5.1 | HP  +318 | Champ 0.52 [f1_b]
S.Corr     | none | F1 Rogue Imp Pack         | Win  22.0% | Loss  78.0% | T  5.1 | HP  +182 | Champ 0.40 [f1_c]
S.Corr     | none | F2 Corrupted Broodlings   | Win  71.0% | Loss  29.0% | T  6.4 | HP +1039 | Champ 0.48 [f2_a]
             Clog:0.1
S.Corr     | none | F2 Corrupted Broodlings   | Win  49.0% | Loss  51.0% | T  5.7 | HP  +440 | Champ 0.11 [f2_b]
S.Corr     | none | F2 Corrupted Broodlings   | Win  74.5% | Loss  25.5% | T  5.9 | HP +1117 | Champ 0.19 [f2_c]
S.Corr     | none | F3 Imp Matriarch          | Win  30.5% | Loss  69.5% | T  6.1 | HP  +291 | Champ 0.22 [f3_a]
S.Corr     | none | F3 Imp Matriarch          | Win  49.5% | Loss  50.5% | T  8.5 | HP  +939 | Champ 0.41 [f3_b]
             Clog:0.1
S.Corr     | none | F3 Imp Matriarch          | Win  53.0% | Loss  47.0% | T  6.7 | HP +1053 | Champ 0.34 [f3_c]
--- Act 2 ---
Swarm      | SL   | F4 Abyss Cultist Patrol   | Win  81.5% | Loss  18.5% | T  6.0 | HP +1505 | Champ 0.29 [f4_a]
             Det:0.9 | Clog:0.1
Swarm      | IT   | F4 Abyss Cultist Patrol   | Win  84.0% | Loss  16.0% | T  5.9 | HP +1525 | Champ 0.32 [f4_a]
             Det:0.9 | Clog:0.2
Swarm      | MS   | F4 Abyss Cultist Patrol   | Win  79.0% | Loss  21.0% | T  6.2 | HP +1492 | Champ 0.36 [f4_a]
             Det:1.2 | Clog:0.1
Swarm      | BS   | F4 Abyss Cultist Patrol   | Win  80.0% | Loss  20.0% | T  6.5 | HP +1462 | Champ 0.43 [f4_a]
             Det:1.4 | Clog:0.1
Swarm      | SL   | F4 Abyss Cultist Patrol   | Win  90.0% | Loss  10.0% | T  6.2 | HP +2041 | Champ 0.38 [f4_b]
             Det:1.8
Swarm      | IT   | F4 Abyss Cultist Patrol   | Win  87.0% | Loss  13.0% | T  6.1 | HP +1922 | Champ 0.45 [f4_b]
             Det:2.0
Swarm      | MS   | F4 Abyss Cultist Patrol   | Win  78.5% | Loss  21.5% | T  6.4 | HP +1672 | Champ 0.47 [f4_b]
             Det:2.0
Swarm      | BS   | F4 Abyss Cultist Patrol   | Win  89.0% | Loss  11.0% | T  6.6 | HP +1843 | Champ 0.54 [f4_b]
             Det:2.2
Swarm      | SL   | F5 Void Ritualist         | Win  87.0% | Loss  13.0% | T  6.3 | HP +2177 | Champ 0.41 [f5_a]
             Rit:0.6
Swarm      | IT   | F5 Void Ritualist         | Win  95.5% | Loss   4.5% | T  6.1 | HP +2385 | Champ 0.31 [f5_a]
             Rit:0.4
Swarm      | MS   | F5 Void Ritualist         | Win  83.0% | Loss  17.0% | T  6.6 | HP +2090 | Champ 0.44 [f5_a]
             Rit:0.6
Swarm      | BS   | F5 Void Ritualist         | Win  88.5% | Loss  11.5% | T  6.6 | HP +2217 | Champ 0.39 [f5_a]
             Rit:0.5
Swarm      | SL   | F6 Corrupted Handler      | Win  92.0% | Loss   8.0% | T  8.2 | HP +2155 | Champ 0.89 [f6_a]
             Aura:303 | Clog:0.9
Swarm      | IT   | F6 Corrupted Handler      | Win  91.5% | Loss   8.5% | T  8.5 | HP +2138 | Champ 0.83 [f6_a]
             Aura:267 | Clog:1.1
Swarm      | MS   | F6 Corrupted Handler      | Win  88.0% | Loss  12.0% | T  8.7 | HP +2081 | Champ 0.84 [f6_a]
             Aura:301 | Clog:1.2
Swarm      | BS   | F6 Corrupted Handler      | Win  87.5% | Loss  12.5% | T  8.9 | HP +2052 | Champ 0.86 [f6_a]
             Aura:319 | Clog:1.1
Voidbolt   | SL   | F4 Abyss Cultist Patrol   | Win  94.5% | Loss   5.5% | T  6.5 | HP +1472 | Champ 0.52 [f4_a]
             Det:1.2 | Clog:0.5 | Plg:1.6/0.2 | VB:1.6x/2805dmg | Imp:328
Voidbolt   | IT   | F4 Abyss Cultist Patrol   | Win  94.5% | Loss   5.5% | T  6.5 | HP +1442 | Champ 0.52 [f4_a]
             Det:1.2 | Clog:0.5 | Plg:1.4/0.1 | VB:1.4x/2762dmg | Imp:370
Voidbolt   | MS   | F4 Abyss Cultist Patrol   | Win  91.5% | Loss   8.5% | T  6.6 | HP +1332 | Champ 0.34 [f4_a]
             Det:1.2 | Clog:0.5 | Plg:1.5/0.2 | VB:1.6x/2773dmg | Imp:285
Voidbolt   | BS   | F4 Abyss Cultist Patrol   | Win  94.0% | Loss   6.0% | T  7.0 | HP +1108 | Champ 0.47 [f4_a]
             Det:1.3 | Clog:0.4 | Plg:1.5/0.3 | VB:1.6x/2782dmg | Imp:298
Voidbolt   | SL   | F4 Abyss Cultist Patrol   | Win  94.0% | Loss   6.0% | T  6.6 | HP +1476 | Champ 0.32 [f4_b]
             Det:1.7 | Clog:0.4 | Plg:1.7/0.1 | VB:1.7x/2866dmg | Imp:322
Voidbolt   | IT   | F4 Abyss Cultist Patrol   | Win  93.5% | Loss   6.5% | T  6.3 | HP +1623 | Champ 0.33 [f4_b]
             Det:1.7 | Clog:0.4 | Plg:1.3/0.2 | VB:1.5x/2800dmg | Imp:380
Voidbolt   | MS   | F4 Abyss Cultist Patrol   | Win  89.0% | Loss  11.0% | T  6.5 | HP +1520 | Champ 0.24 [f4_b]
             Det:1.8 | Clog:0.4 | Plg:1.3/0.2 | VB:1.6x/2814dmg | Imp:286
Voidbolt   | BS   | F4 Abyss Cultist Patrol   | Win  97.0% | Loss   3.0% | T  7.1 | HP +1282 | Champ 0.27 [f4_b]
             Det:1.7 | Clog:0.3 | Plg:1.5/0.1 | VB:1.6x/2855dmg | Imp:294
Voidbolt   | SL   | F5 Void Ritualist         | Win  91.0% | Loss   9.0% | T  6.5 | HP +1695 | Champ 0.46 [f5_a]
             Rit:0.5 | Plg:1.6/0.0 | VB:1.7x/2884dmg | Imp:329
Voidbolt   | IT   | F5 Void Ritualist         | Win  86.0% | Loss  14.0% | T  6.3 | HP +1635 | Champ 0.49 [f5_a]
             Rit:0.6 | Plg:1.3/0.0 | VB:1.4x/2819dmg | Imp:373
Voidbolt   | MS   | F5 Void Ritualist         | Win  85.0% | Loss  15.0% | T  6.6 | HP +1530 | Champ 0.44 [f5_a]
             Rit:0.5 | Plg:1.3/0.0 | VB:1.5x/2896dmg | Imp:302
Voidbolt   | BS   | F5 Void Ritualist         | Win  90.5% | Loss   9.5% | T  7.0 | HP +1237 | Champ 0.50 [f5_a]
             Rit:0.6 | Plg:1.4/0.1 | VB:1.6x/2969dmg | Imp:306
Voidbolt   | SL   | F6 Corrupted Handler      | Win  80.0% | Loss  20.0% | T  7.5 | HP +1182 | Champ 0.82 [f6_a]
             Aura:323 | Clog:1.5 | Plg:1.8/0.4 | VB:1.9x/3859dmg | Imp:358
Voidbolt   | IT   | F6 Corrupted Handler      | Win  86.5% | Loss  13.5% | T  7.5 | HP +1344 | Champ 0.82 [f6_a]
             Aura:316 | Clog:1.6 | Plg:1.5/0.3 | VB:1.7x/3791dmg | Imp:418
Voidbolt   | MS   | F6 Corrupted Handler      | Win  70.0% | Loss  30.0% | T  7.7 | HP  +956 | Champ 0.78 [f6_a]
             Aura:340 | Clog:1.5 | Plg:1.5/0.1 | VB:1.8x/3687dmg | Imp:332
Voidbolt   | BS   | F6 Corrupted Handler      | Win  76.0% | Loss  24.0% | T  8.4 | HP  +853 | Champ 0.84 [f6_a]
             Aura:273 | Clog:1.8 | Plg:1.7/0.3 | VB:1.9x/3962dmg | Imp:347
DeathCircle | SL   | F4 Abyss Cultist Patrol   | Win  88.0% | Loss  12.0% | T  5.9 | HP +1970 | Champ 0.42 [f4_a]
             Det:1.2 | PRit:1.3 | Clog:0.2
DeathCircle | IT   | F4 Abyss Cultist Patrol   | Win  88.0% | Loss  12.0% | T  6.0 | HP +2130 | Champ 0.45 [f4_a]
             Det:1.3 | PRit:1.1 | Clog:0.2
DeathCircle | MS   | F4 Abyss Cultist Patrol   | Win  79.5% | Loss  20.5% | T  6.5 | HP +1898 | Champ 0.56 [f4_a]
             Det:1.6 | PRit:1.3 | Clog:0.2
DeathCircle | BS   | F4 Abyss Cultist Patrol   | Win  80.0% | Loss  20.0% | T  6.7 | HP +1680 | Champ 0.54 [f4_a]
             Det:1.6 | PRit:1.3 | Clog:0.2
DeathCircle | SL   | F4 Abyss Cultist Patrol   | Win  72.0% | Loss  28.0% | T  6.9 | HP +1649 | Champ 0.65 [f4_b]
             Det:2.2 | PRit:1.5 | Clog:0.2
DeathCircle | IT   | F4 Abyss Cultist Patrol   | Win  70.5% | Loss  29.5% | T  6.6 | HP +1920 | Champ 0.57 [f4_b]
             Det:2.1 | PRit:1.3 | Clog:0.3
DeathCircle | MS   | F4 Abyss Cultist Patrol   | Win  66.0% | Loss  34.0% | T  7.2 | HP +1579 | Champ 0.61 [f4_b]
             Det:2.4 | PRit:1.4 | Clog:0.2
DeathCircle | BS   | F4 Abyss Cultist Patrol   | Win  62.0% | Loss  38.0% | T  7.8 | HP +1371 | Champ 0.72 [f4_b]
             Det:2.6 | PRit:1.5 | Clog:0.2
DeathCircle | SL   | F5 Void Ritualist         | Win  85.0% | Loss  15.0% | T  5.9 | HP +2458 | Champ 0.32 [f5_a]
             Rit:0.5 | PRit:1.2
DeathCircle | IT   | F5 Void Ritualist         | Win  82.0% | Loss  18.0% | T  6.1 | HP +2422 | Champ 0.39 [f5_a]
             Rit:0.6 | PRit:1.1
DeathCircle | MS   | F5 Void Ritualist         | Win  71.5% | Loss  28.5% | T  6.7 | HP +2085 | Champ 0.48 [f5_a]
             Rit:0.6 | PRit:1.4
DeathCircle | BS   | F5 Void Ritualist         | Win  68.5% | Loss  31.5% | T  7.0 | HP +1835 | Champ 0.52 [f5_a]
             Rit:0.8 | PRit:1.3
DeathCircle | SL   | F6 Corrupted Handler      | Win  73.5% | Loss  26.5% | T  8.6 | HP +1920 | Champ 0.85 [f6_a]
             PRit:1.7 | Aura:326 | Clog:1.7
DeathCircle | IT   | F6 Corrupted Handler      | Win  73.0% | Loss  27.0% | T  8.5 | HP +2126 | Champ 0.86 [f6_a]
             PRit:1.5 | Aura:324 | Clog:1.8
DeathCircle | MS   | F6 Corrupted Handler      | Win  69.5% | Loss  30.5% | T  9.0 | HP +1949 | Champ 0.81 [f6_a]
             PRit:1.5 | Aura:321 | Clog:1.9
DeathCircle | BS   | F6 Corrupted Handler      | Win  62.5% | Loss  37.5% | T  9.9 | HP +1656 | Champ 0.87 [f6_a]
             PRit:1.5 | Aura:311 | Clog:2.0
S.Flesh    | SL   | F4 Abyss Cultist Patrol   | Win  71.5% | Loss  28.5% | T  5.9 | HP +1192 | Champ 0.28 [f4_a]
             Det:1.0 | Clog:0.3
S.Flesh    | IT   | F4 Abyss Cultist Patrol   | Win  50.0% | Loss  50.0% | T  6.5 | HP  +750 | Champ 0.39 [f4_a]
             Det:1.4 | Clog:0.5
S.Flesh    | MS   | F4 Abyss Cultist Patrol   | Win  64.5% | Loss  35.5% | T  6.2 | HP +1081 | Champ 0.29 [f4_a]
             Det:1.1 | Clog:0.3
S.Flesh    | BS   | F4 Abyss Cultist Patrol   | Win  70.0% | Loss  30.0% | T  6.4 | HP +1091 | Champ 0.32 [f4_a]
             Det:1.2 | Clog:0.2
S.Flesh    | SL   | F4 Abyss Cultist Patrol   | Win  73.0% | Loss  27.0% | T  6.2 | HP +1526 | Champ 0.42 [f4_b]
             Det:1.8
S.Flesh    | IT   | F4 Abyss Cultist Patrol   | Win  54.0% | Loss  46.0% | T  6.7 | HP  +972 | Champ 0.52 [f4_b]
             Det:2.1 | Clog:0.1
S.Flesh    | MS   | F4 Abyss Cultist Patrol   | Win  59.5% | Loss  40.5% | T  6.7 | HP +1222 | Champ 0.48 [f4_b]
             Det:2.2 | Clog:0.2
S.Flesh    | BS   | F4 Abyss Cultist Patrol   | Win  70.0% | Loss  30.0% | T  7.1 | HP +1234 | Champ 0.54 [f4_b]
             Det:2.2 | Clog:0.1
S.Flesh    | SL   | F5 Void Ritualist         | Win  76.0% | Loss  24.0% | T  6.7 | HP +1706 | Champ 0.42 [f5_a]
             Rit:0.6
S.Flesh    | IT   | F5 Void Ritualist         | Win  54.0% | Loss  46.0% | T  7.0 | HP +1140 | Champ 0.44 [f5_a]
             Rit:0.8
S.Flesh    | MS   | F5 Void Ritualist         | Win  72.5% | Loss  27.5% | T  6.5 | HP +1638 | Champ 0.44 [f5_a]
             Rit:0.6
S.Flesh    | BS   | F5 Void Ritualist         | Win  72.5% | Loss  27.5% | T  7.2 | HP +1594 | Champ 0.41 [f5_a]
             Rit:0.7
S.Flesh    | SL   | F6 Corrupted Handler      | Win  42.5% | Loss  57.5% | T  9.4 | HP  +873 | Champ 0.87 [f6_a]
             Aura:253 | Clog:2.5
S.Flesh    | IT   | F6 Corrupted Handler      | Win  38.5% | Loss  61.5% | T 10.0 | HP  +754 | Champ 0.90 [f6_a]
             Aura:221 | Clog:2.6
S.Flesh    | MS   | F6 Corrupted Handler      | Win  40.5% | Loss  59.5% | T 10.0 | HP  +831 | Champ 0.89 [f6_a]
             Aura:272 | Clog:2.4
S.Flesh    | BS   | F6 Corrupted Handler      | Win  35.0% | Loss  65.0% | T 10.9 | HP  +701 | Champ 0.90 [f6_a]
             Aura:264 | Clog:2.7
S.Forge    | SL   | F4 Abyss Cultist Patrol   | Win  25.5% | Loss  74.5% | T  6.5 | HP  +264 | Champ 0.47 [f4_a]
             Det:1.4 | Clog:0.3
S.Forge    | IT   | F4 Abyss Cultist Patrol   | Win  23.0% | Loss  77.0% | T  6.3 | HP  +263 | Champ 0.45 [f4_a]
             Det:1.3 | Clog:0.4
S.Forge    | MS   | F4 Abyss Cultist Patrol   | Win  23.5% | Loss  76.5% | T  6.5 | HP  +177 | Champ 0.39 [f4_a]
             Det:1.3 | Clog:0.3
S.Forge    | BS   | F4 Abyss Cultist Patrol   | Win  25.5% | Loss  74.5% | T  6.9 | HP  +232 | Champ 0.52 [f4_a]
             Det:1.6 | Clog:0.2
S.Forge    | SL   | F4 Abyss Cultist Patrol   | Win  30.5% | Loss  69.5% | T  6.9 | HP  +310 | Champ 0.55 [f4_b]
             Det:2.1
S.Forge    | IT   | F4 Abyss Cultist Patrol   | Win  22.5% | Loss  77.5% | T  6.9 | HP  +226 | Champ 0.61 [f4_b]
             Det:2.3 | Clog:0.1
S.Forge    | MS   | F4 Abyss Cultist Patrol   | Win  19.5% | Loss  80.5% | T  6.9 | HP  +131 | Champ 0.53 [f4_b]
             Det:2.3
S.Forge    | BS   | F4 Abyss Cultist Patrol   | Win  17.5% | Loss  82.5% | T  7.5 | HP  +103 | Champ 0.67 [f4_b]
             Det:2.5
S.Forge    | SL   | F5 Void Ritualist         | Win  29.5% | Loss  70.5% | T  7.3 | HP  +455 | Champ 0.57 [f5_a]
             Rit:0.9
S.Forge    | IT   | F5 Void Ritualist         | Win  36.0% | Loss  64.0% | T  7.2 | HP  +545 | Champ 0.62 [f5_a]
             Rit:0.8
S.Forge    | MS   | F5 Void Ritualist         | Win  27.0% | Loss  73.0% | T  7.2 | HP  +362 | Champ 0.56 [f5_a]
             Rit:0.8
S.Forge    | BS   | F5 Void Ritualist         | Win  24.0% | Loss  76.0% | T  7.8 | HP  +257 | Champ 0.71 [f5_a]
             Rit:1.1
S.Forge    | SL   | F6 Corrupted Handler      | Win  35.0% | Loss  65.0% | T 12.0 | HP  +646 | Champ 0.97 [f6_a]
             Aura:247 | Clog:1.7
S.Forge    | IT   | F6 Corrupted Handler      | Win  34.5% | Loss  65.5% | T 12.1 | HP  +581 | Champ 0.93 [f6_a]
             Aura:277 | Clog:1.9
S.Forge    | MS   | F6 Corrupted Handler      | Win  29.0% | Loss  71.0% | T 11.8 | HP  +509 | Champ 0.92 [f6_a]
             Aura:273 | Clog:1.6
S.Forge    | BS   | F6 Corrupted Handler      | Win  29.5% | Loss  70.5% | T 12.8 | HP  +459 | Champ 0.95 [f6_a]
             Aura:249 | Clog:1.8
S.Corr     | SL   | F4 Abyss Cultist Patrol   | Win  85.5% | Loss  14.5% | T  6.1 | HP +1407 | Champ 0.31 [f4_a]
             Det:1.0 | Clog:0.5
S.Corr     | IT   | F4 Abyss Cultist Patrol   | Win  81.0% | Loss  19.0% | T  6.0 | HP +1268 | Champ 0.24 [f4_a]
             Det:0.8 | Clog:0.7
S.Corr     | MS   | F4 Abyss Cultist Patrol   | Win  87.5% | Loss  12.5% | T  6.1 | HP +1377 | Champ 0.24 [f4_a]
             Det:0.9 | Clog:0.7
S.Corr     | BS   | F4 Abyss Cultist Patrol   | Win  81.0% | Loss  19.0% | T  6.3 | HP +1203 | Champ 0.26 [f4_a]
             Det:1.0 | Clog:0.6
S.Corr     | SL   | F4 Abyss Cultist Patrol   | Win  83.5% | Loss  16.5% | T  6.5 | HP +1315 | Champ 0.58 [f4_b]
             Det:2.1 | Clog:0.6
S.Corr     | IT   | F4 Abyss Cultist Patrol   | Win  80.5% | Loss  19.5% | T  6.6 | HP +1216 | Champ 0.55 [f4_b]
             Det:1.9 | Clog:0.7
S.Corr     | MS   | F4 Abyss Cultist Patrol   | Win  66.0% | Loss  34.0% | T  6.9 | HP +1055 | Champ 0.54 [f4_b]
             Det:2.1 | Clog:0.6
S.Corr     | BS   | F4 Abyss Cultist Patrol   | Win  76.0% | Loss  24.0% | T  7.0 | HP +1039 | Champ 0.64 [f4_b]
             Det:2.1 | Clog:0.5
S.Corr     | SL   | F5 Void Ritualist         | Win  68.5% | Loss  31.5% | T  6.9 | HP +1006 | Champ 0.40 [f5_a]
             Rit:0.5 | Clog:0.1
S.Corr     | IT   | F5 Void Ritualist         | Win  64.0% | Loss  36.0% | T  6.8 | HP  +908 | Champ 0.47 [f5_a]
             Rit:0.6 | Clog:0.1
S.Corr     | MS   | F5 Void Ritualist         | Win  40.0% | Loss  60.0% | T  7.1 | HP  +554 | Champ 0.52 [f5_a]
             Rit:0.7
S.Corr     | BS   | F5 Void Ritualist         | Win  48.0% | Loss  52.0% | T  6.7 | HP +1053 | Champ 0.34 [f3_c]
S.Corr     | SL   | F6 Corrupted Handler      | Win  43.5% | Loss  56.5% | T 11.7 | HP  +834 | Champ 0.92 [f6_a]
             Aura:270 | Clog:2.5
S.Corr     | IT   | F6 Corrupted Handler      | Win  36.5% | Loss  63.5% | T 11.4 | HP  +655 | Champ 0.89 [f6_a]
             Aura:272 | Clog:2.6
S.Corr     | MS   | F6 Corrupted Handler      | Win  33.5% | Loss  66.0% | T 11.8 | HP  +555 | Champ 0.90 [f6_a]
             Aura:302 | Clog:2.8
S.Corr     | BS   | F6 Corrupted Handler      | Win  29.5% | Loss  70.5% | T 12.6 | HP  +500 | Champ 0.91 [f6_a]
             Aura:275 | Clog:2.8
```

Trailing `ERROR: 39 resources still in use at exit` is a known Godot teardown artifact (BoardSlot RefCounted leak in headless), not a sim failure. Ignored.
