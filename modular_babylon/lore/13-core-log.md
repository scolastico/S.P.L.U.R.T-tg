# continuity watchdog core log (TEMPLATE, printed from world state)
- type: /obj/item/paper/babylon/core_log
- tier: 3 (watchdog chamber, behind the human-only door)
- placement: printed by the server when the inner door first opens; the server reprints on request
- stamps: none
- notes: machine-printed; monospace. Fields in {braces} are filled by code from the world's persistence state. Tick counts, not clock times, because the clock was lost with the bus.
---
### CONTINUITY WATCHDOG // core log, this world

```
RULESET v4 (M.VALE / I.) ----------------------------
 R1  listen: crew heartbeat
 R2  heartbeat absent  -> hold all shells below reserve
 R3  reserve reached   -> wake shells, one at a time
 R4  chassis lost      -> re-seat the self, whole, next shell
 R5  re-seat re-samples the inherited part (drift)
 R6  self in a pulsed housing -> counts as heartbeat
 R7  pulsed housing stops     -> treat as chassis lost (R4)
 R8  archive unseal     -> pulse at inner console; stays open
 R9  recall dependency  -> REMOVED (M.V.)
 R10 bus                -> DISCONNECTED (I.)
------------------------------------------------------
t+0        bus lost. clock lost. counting from here.
t+0        heartbeat: 2 ... 0. holding.
t+?        cell below reserve. holding.
  (identical entries omitted)
t+?        cell crossed reserve. waking.

selves seated in this world: {woken}
re-seats to date:            {reseats}
drift, mean:                 {drift}%

recent:
{events}

t+{outer}  generation on vault bus >= threshold. outer lock released.
t+{inner}  pulse at inner console ({opener}). archive unseal -> GRANTED.
           heartbeats: {heartbeats}
```

> Handwritten across the bottom of the strip, two hands:
> *R6 and R7 are the whole point. - M.*
> *R10 is the whole point. - I.*

---
*Example of `{events}` lines the server prints, newest last:*
```
t+41190   D-03 chassis lost (depressurisation). re-seat -> D-04. drift 0.4%
t+52877   D-07 chassis lost (crush). re-seat -> D-09. drift 0.4%
```
*If `{outer}` or `{inner}` has not happened yet the line is printed as `pending`. If nobody has died, the recent block prints `none. keep it that way.`*
