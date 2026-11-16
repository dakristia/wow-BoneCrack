# BoneCrack

A WoW Forever addon that plays a bone-crack sound when you take fall damage.

## Install

In WowUp, choose "Install from URL" and paste `https://github.com/dakristia/wow-BoneCrack`.

## How it works

- Your own falls: the client hides your health from addons, so BoneCrack plays when you land after at least 1.2 seconds of free fall, unless you land in water or are flying.
- Group members: their health is hidden too, so BoneCrack can only hear a group member's fall when they also run BoneCrack. Their addon sends a party or raid addon message. Addon messages are blocked inside instances, so this only works in the open world.

## Commands

- `/bonecrack` plays the sound.
- `/bonecrack debug` turns on chat output that shows what the addon sees.
