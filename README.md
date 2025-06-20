# Gas Station Job Script for Qbox (QBCore-based) FiveM Server

---

## Overview

This script implements a **Gas Station Job** system for FiveM servers using the Qbox framework (QBCore-based). Players can sign on as gas station clerks, manage store transactions, interact with NPC shoppers, handle robberies, and perform various job-related tasks. The system supports:

- Player sign-on and sign-off at multiple gas stations
- NPC clerks that appear when no player is working
- Shopper purchases with payment methods (cash/bank)
- Robbery mechanics with register and safe targets
- Police alerts and cooldown timers for robberies
- Task payouts for completed jobs
- Configurable store inventory and prices

---

## Features

- **Multi-station support:** Define multiple gas stations with unique locations and inventories.
- **NPC clerks:** Automatically spawn NPC clerks when no player is working.
- **Store inventory:** Customize items sold, prices, and payment methods.
- **Robbery system:** Players can rob the register (lockpick required) or safe (C4 or hacking).
- **Police dispatch integration:** Sends real-time alerts on robberies.
- **Cooldown management:** Prevents repeated robberies within a cooldown period.
- **Player payouts:** Clerks receive a percentage cut from shopper purchases and task completions.
- **Discord logging:** Optional webhook integration for robbery events and job logs.

---

## Installation

1. Place the script folder inside your FiveM server's `resources` directory.

2. Add the resource to your `server.cfg`:

ensure gasstationjob



3. Ensure you have QBCore (Qbox) framework installed and running.

4. Configure the script by editing the `config.lua` file with your desired gas stations, items, prices, and webhook URLs.

---

## Configuration

Edit `config.lua` to customize:

- **Stations:** Define gas station names, coordinates, NPC models, starting funds for registers and safes.
- **StoreInventory:** Set items sold in stations with prices.
- **PayoutPercentage:** The fraction of shopper purchase price given to clerks (e.g., 0.1 for 10%).
- **RobberyCooldownDuration:** Cooldown time (seconds) after a robbery.
- **RobberyAmounts:** Max amounts that can be stolen from registers and safes.
- **DiscordWebhook:** URL for logging robbery alerts.

---

## Usage

- Players can open the job menu to select a gas station and sign on as clerks.
- While signed on, players perform tasks like restocking shelves, serving NPC shoppers, and handling sales.
- Robbery minigames (lockpicking or hacking/C4) can be triggered client-side to rob registers or safes.
- Police are alerted automatically on robberies.
- Clerks earn money from shopper purchases and completed tasks.
- Players can sign off to return the station to NPC clerk control.

---

## Dependencies

- [QBCore Framework (Qbox)](https://github.com/qbcore-framework/qb-core)
- Police dispatch system compatible with `ps-dispatch` or similar
- ox_lib (for notifications) — optional but recommended

---

## Commands

- `/gasstationstatus` — Shows current gas station job status (admin/debug only, requires `Config.Debug = true`)

---

## Known Issues & TODO

- Robbery minigames need proper client-side implementations (lockpicking, hacking, C4 placement).
- NPC shopper behavior and AI can be further enhanced.
- Add player-owned business pickup requests and job list integration.
- Expand inventory management with dynamic restocking.
- Improve UI and client-server communication.

---

## Support & Contribution

Feel free to open issues or submit pull requests on the GitHub repository. For questions or help, join the QBCore community Discord.

---

## License

This script is provided as-is under the MIT License. You may modify and distribute it freely but please credit the original author.

---

**Enjoy the Gas Station Job system!** 🚗⛽💼
