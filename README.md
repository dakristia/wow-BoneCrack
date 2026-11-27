# BoneCrack

A WoW Forever addon that plays a bone-crack sound when you take fall damage.

## Install

In WowUp, choose "Install from URL" and paste `https://github.com/dakristia/wow-BoneCrack`.

## How it works

- Your own falls: the client hides your health from addons, so BoneCrack plays when you land after a fall and the client reports a WOUND to you right at the landing. If the client hides that too, it falls back to air time of at least 1.6 seconds. In combat a mob's hit is also a WOUND, so a landing in combat also needs at least 1.6 seconds of air time. It stays silent if you land in water or are flying.
- Group members: their health is hidden too, so BoneCrack can only hear a group member's fall when they also run BoneCrack. Their addon sends a party or raid addon message: first a details message (`fell2:<loss>:<air>:<dead>:<map>`) and then the plain `fell` that older versions understand. A receiver plays the sound once for the pair and sorts the fall into a damage tier (small, medium, big or death). Addon messages are blocked inside instances, so this only works in the open world.

## Commands

- `/bonecrack` plays the sound. It ignores the cooldown and the cap, so it works as a test.
- `/bonecrack cooldown <seconds>` sets the time between two cracks. The default is 0.5 seconds.
- `/bonecrack cooldownscope person|group` sets whether each person has their own cooldown or the whole group shares one. The default is per person.
- `/bonecrack cap <n>` sets the most cracks per second. The default is 10, and 0 turns the cap off. A high cap or no cap can cut off other game sounds, so BoneCrack warns you when you set one.
- `/bonecrack channel Master|SFX|Music|Ambience|Dialog` sets the sound channel the crack plays on, so the matching volume slider controls it. The default is Master.
- `/bonecrack debug` turns debug logging on or off. WoW remembers the setting across sessions. Debug prints nothing to chat. It saves what the addon sees to `BoneCrackDebugLog` in the SavedVariables file, which WoW writes on /reload or logout. The log is kept between sessions and holds at most the newest 500 lines. Read it with `bin/debuglog BoneCrack` from wow-addon-workshop.
- `/bonecrack clearlog` clears the saved debug log.
- `/bonecrack popups` turns the party pop-ups on or off, and `/bonecrack raidpopups` the raid pop-ups. All pop-ups are off by default, so out of the box BoneCrack only plays the sound. A pop-up shows on the Blizzard party, raid or player frame of whoever fell, and it grows with the damage. Players without Blizzard frames get no pop-up. The same settings are on the BoneCrack page in the game options, under AddOns.
- `/bonecrack instances` turns BoneCrack on or off inside dungeons, raids and other instances. It is off by default, because instances hide more from addons and BoneCrack may cause Lua errors there.
- `/bonecrack selfpopup` turns the pop-up for your own falls on or off. It is off by default.
- `/bonecrack panel` opens a test panel with buttons for the test pop-ups, the sound and the settings.
- `/bonecrack test [player|party1-4|group] [small|medium|big|death]` shows a pop-up without a fall.
