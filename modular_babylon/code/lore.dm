// Optional map additions, compiled only into Babylon. Papers use normal item
// interactions and persist as their own types when carried, moved or saved.
/obj/item/paper/babylon
	can_become_message_in_bottle = FALSE

/obj/item/paper/babylon/watchdog
	name = "creased continuity maintenance sheet"
	default_raw_text = {"<h3>BABYLON // CONTINUITY WATCHDOG</h3>
Maintenance copy, engineering.<br><br>
If the crew heartbeat remains absent, suspend all drones below reserve threshold.
Reactivate when a chassis can survive long enough to attempt repairs. Do not wait for a command acknowledgement; the uplink may never return.<br><br>
Emergency stores are issued once per identity. Replacement shells are not provisioned.
Tools remain with the old chassis. This is a repair programme, not a supply line.<br><br>
Margin note, M. Vale: <i>Give them a chance to finish what we couldn't. Remove the recall dependency.</i>"}

/obj/item/paper/babylon/research
	name = "Vale's torn laboratory notebook page"
	default_raw_text = {"<h3>PROJECT MNEMOSYNE // personal notes</h3>
The board keeps asking whether a copy of a memory is a person. I asked whether losing the original makes the copy less afraid.<br><br>
The drone lattice held a pattern through a complete power interruption. The synthetic neural scaffold remains an unfinished proposal; the transfer rig was never authorised.<br><br>
If a mind is only allowed one housing, continuity is a privilege of whoever sells the housing.<br><br>
Last line, heavily scored out: <s>Request permission for human trials.</s><br>
Underneath: <i>First make somewhere safe to wake up.</i>"}

/obj/item/paper/babylon/triage
	name = "vacuum-stained triage tally"
	default_raw_text = {"<h3>MEDICAL // evacuation tally</h3>
Departure groups: 12 / 9 / 7. Destination confirmations: NONE.<br>
The nitrogen reserve was lower than the panel reported. We moved patients before the main pressure alarm sounded.<br><br>
Vale surrendered her seat to the last stretcher. Security called her a flight risk. She laughed so hard she couldn't answer them.<br><br>
I left the equipment I couldn't carry. If a maintenance unit finds this, please keep the ward intact.
It was a good room before all of this.<br><br>-- S. Ren, medical"}

/obj/item/paper/babylon/recall
	name = "sealed operations recall printout"
	default_raw_text = {"<h3>OPERATIONS DIRECTIVE // internal copy</h3>
Terminate Project MNEMOSYNE. Revoke Dr. Mara Vale's command privileges. Recover all neural archive media.
Station reclamation is contingent upon confirmation of archive destruction.<br><br>
03:10 -- Reclassification: ROGUE RESEARCH PERSONNEL.<br>
03:14 -- Station uplink interrupted.<br>
03:17 -- Hull failure reported. Source authentication unavailable.<br><br>
A handwritten query circles the first timestamp: <i>This order was signed before the accident. Who knew?</i>"}

/obj/item/paper/babylon/pressure
	name = "atmospheric fault investigation fragment"
	default_raw_text = {"<h3>FAULT REVIEW // engineering draft</h3>
Pressure transducers failed in sequence, not together. The first impossible reading preceded the control-board resets by twenty-seven seconds.<br><br>
There are outward scorch marks on the relay enclosure. That could be sabotage. It could also be a safety trip doing exactly what it was built to do.
Do not sign a conclusion from a damaged log.<br><br>
Vale asked me to isolate the watchdog from the station bus. I did. Whatever happened to the main computer should not reach the sleeping drones.<br><br>
If you are reading this after a restart, inspect every flow path before trusting an old indicator.<br>-- Ilya, engineering"}

/obj/item/paper/babylon/last_light
	name = "folded note with no signature"
	default_raw_text = {"<i>They called her rogue. She stayed until the last shuttle left.</i><br><br>
I do not know if she saved us or if she was trying to save what we had already become.
There was no time to ask.<br><br>
If the little machines wake, I hope they remember something kinder than the alarms.
I hope they make new rooms instead of only patching the old ones.<br><br>
Leave a light in a window. There should be somewhere to come back to."}
