# BoneCrack

A WoW Forever addon that plays a bone-crack sound when you take fall damage.

## Install

In WowUp, choose "Install from URL" and paste `https://github.com/dakristia/wow-BoneCrack`.

## How it works

- Your own falls: the client hides your health from addons, so BoneCrack plays when you land after a fall and the client reports a WOUND to you right at the landing. If the client hides that too, it falls back to air time of at least 1.6 seconds. In combat a mob's hit is also a WOUND, so a landing in combat also needs at least 1.6 seconds of air time. It stays silent if you land in water or are flying.
- Group members: their health is hidden too, so BoneCrack can only hear a group member's fall when they also run BoneCrack. Their addon sends a party or raid addon message. Addon messages are blocked inside instances, so this only works in the open world.

## Commands

- `/bonecrack` plays the sound.
- `/bonecrack debug` turns on chat output that shows what the addon sees.
