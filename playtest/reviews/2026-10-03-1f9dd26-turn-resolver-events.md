**ascendant turn resolver event report @ 1f9dd26** (pr #15, already merged)
- works as intended? partly. all six cases in the scripted turn resolve correctly in phase order, no ids show up in the text, and the 44/44 tests pass. but the battle and capture lines name only the faction, not "<Faction> army at <Province>". and the scenario can't show 53 gold per half, because neither side owns a full half. the mirrored-income test is the only proof of that number.
- does it land? the rules are clean and easy to explain, and 12 of the 16 lines would make sense to a new player as is. the weak lines are the battles, which are the ones that matter most. "Thornmane Clans (strength 12)" never says which units, so the brief's "say why they lost from the report alone" fails. a tie is settled by "a seeded roll", which is jargon and gives no odds. line 10 says Wildmoor was captured "unopposed" one line after its defenders died on the border. armies are named by where they stand, so "the Aurel Crown army at Crownkeep" means two different armies three lines apart. that will turn to mush once there are 10 armies.
- call: keep the resolver. rework the wording before the ui lands, because the turn report will just display these lines.
- ideas:
  - give every army a stable name (its commander's, or "the Crown's 2nd"), so you can follow one army across lines and across turns.
  - on a tied border swap, have both armies bounce home instead of a coin flip deleting one. it's predictable and still punishes guessing wrong.
  - when a recruit fails for gold, say whether this turn's income would have covered it, so players learn that recruiting is paid before income.
- ui/ux:
  - battle lines 5 and 7: name the units and the outcome, e.g. "Aurel Crown's Knights (20) beat Thornmane Clans' Tuskers (17) in Blackwood. the Tuskers were destroyed, the Knights took no losses."
  - lines 5 and 10: "met as they swapped places" should be "tried to swap places". "seeded roll" should be "a 50/50 roll". Wildmoor should read "its defenders marched out and died on the Thornvale border", not "unopposed".
  - lines 1 and 14: say what happened as a result ("the War Bear stays at Deepwood"; "the third Knights order was rejected: they cost 20 gold, Aurel Crown had 10"). drop the lone "you". also group moves by destination, so both Blackwood moves sit together and not in id order with the Captain's move in between.

there's no ui yet, so there are no screenshots. this verdict comes from the actual event output of the test's scripted turn with seed 2026.
