# League of Legends reference: ranked, mastery and levels

Researched in October 2026 (web search of the League of Legends Wiki pages on ranked, champion mastery and summoner
level, and Riot's patch notes) as the model for Defend The Master's ranked ladder, hero mastery and account level.
Mechanics only: no names, art or text are taken over. The numbers we use live in `src/shared/Config.luau`
(`Config.Ranked`, `Config.Mastery`, `Config.Account`, `Config.Rewards.Grades`).

## Ranked

| League | Defend The Master |
| --- | --- |
| About +/-20 LP a game when the rating matches the rank; above it more for a win and less for a loss, roughly 10 to 30 | `Win`/`Loss` 20, `Swing` 10 per `SwingPer` 20 rating points apart, clamped to +/-10 |
| 5 placement games, no LP lost in them, placed at most in Diamond III | `Placements` 5 (rating moves at double K), placed at most at `PlaceCap` (tier 7, division 3) |
| 100 LP a division, the surplus carries over on promotion | the same; promotion loops while LP >= 100 |
| Losing below 0 LP inside a tier drops a division with the LP carried over | the same (`+100` into the division below) |
| A new tier gives a demotion shield for some games, only after promoting into it | `Shield` 10 games, set only when the tier rose |
| Dropping out of a tier lands on 25, 50 or 75 LP after the hidden rating | `DemoteLp` {25, 50, 75}, chosen in `DemoteBand` 100 rating steps |
| Annual soft reset of at least 4 divisions, then placements again with a ceiling | `Reset` 4 divisions; the lowered rank is the placements' ceiling |
| Ranked opens at account level 30, with 20 champions and 10 normal games | owner's choice: account level 15 (`Level`) and 10 Quick Play games (`QuickPlays`); 8 heroes (`Heroes`) once that many exist |
| Unplaced players show as unranked and are not on the ladder | `Ranks.placed`; the ladder and the rank attributes skip them |

Distribution reference: Gold is the largest tier; Diamond and up about 4.65% of players, Master and up about 0.73%.

## Champion mastery (our hero mastery)

- Levels have no cap. Points to each level: level 2 1,800; level 3 4,200; level 4 6,600; level 5 9,000; level 6
 10,000; every level from 7 on 11,000. Level 10 takes 75,600 points in all (`Config.Mastery.Steps`).
- From level 5 a level also asks Marks of Mastery: 1 for levels 5 to 9, 2 from level 10 (`MarksFrom`, `MarksTop`).
- Marks come from the season's milestone track: one game at A- (1 mark), again A- (1), one at S- (2), again S- (2),
 then two games at S- per mark, repeating. Track and unused marks reset each season (`Track`, `Bonus`).
- Points per game follow the grade and the result. Ours: S 600, A 500, B 400, C 300, D 200, +/-30 for a + or - grade,
 +100 for a win (`Points`, `Sign`, `Win`). Measured with `Shared.Mastery` (2026-10-28): grades in turn B, A, A-, S-
 with half the games won reach level 5 after 41 games, 9 after 121 and 10 after 142. A player who never gets an S-
 earns only the two A- marks a season and stops at level 6 until the next season, as in League.
- A crest per level 1 to 10, after that the level on the plate; level 10 gives the hero's title
 (`Title` 10, `Assets.MasteryCrests`).
- 15 grades, S+ to D- (`Config.Rewards.Grades`, shown with `Assets.GradeSeals`).

## Levels

- The account (summoner) level has no cap: the XP a level asks rises to a plateau and then stays the same
 (`Config.Account`: 300 for level 2, +50 a level up to level 30, then flat).
- The champion's level inside a match (1 to 18 in League) is separate from mastery and resets every game. Ours runs to
 `Config.Progress.MaxLevel` 12 and resets every match as well.
