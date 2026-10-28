-- The images the game uploaded itself (drawn by Tools/ui_textures.py into Art/UI/ and uploaded through Studio).
return {
	IndicatorDisc = "rbxassetid://73051491375364",
	IndicatorRing = "rbxassetid://139229762314134",
	IndicatorCone = "rbxassetid://81107745868411",
	IndicatorArrowShaft = "rbxassetid://114442048137970",
	IndicatorArrowHead = "rbxassetid://91862876852796",
	CrosshairNeutral = "rbxassetid://128336196823656",
	CrosshairEnemy = "rbxassetid://107422997181186",
	CrosshairAlly = "rbxassetid://129075895576362",
	HudCrown = "rbxassetid://101598854323035",
	-- The Sun Crown from the front (Art/Icons/Crown/SunCrownFront.png, Tools/render_crown_icon.py), worn by the
	-- portrait on the banner when a hero takes it (KillFeed).
	SunCrown = "rbxassetid://108877337730260",
	HudCoin = "rbxassetid://127769238687652",
	-- The menu's icons (one GenerateImage sheet in design 13's look, Art/Icons/concepts/menu_icons_sheet.jpg, cut by
	-- Tools/cut_icons.py into Art/Icons/Menu): the back arrow, the settings gear, the pass's double-XP potion, the
	-- ladder's trophy and the padlock of what is locked.
	MenuBack = "rbxassetid://120094976844168",
	MenuGear = "rbxassetid://122274012051947",
	MenuBoost = "rbxassetid://114387804158897",
	MenuTrophy = "rbxassetid://94424280113656",
	MenuLock = "rbxassetid://127375543575027",
	-- The hero mastery crests, level 1 to 10, each with an empty plate for the level (two Meshy sheets in the
	-- logo's style, Art/Icons/concepts/mastery_crests_*, cut into Art/Icons/Mastery), and the grade seals by letter
	-- (Art/Icons/concepts/grade_seals_sheet.png, cut by Tools/cut_icons.py into Art/Icons/Grades).
	MasteryCrests = {
		"rbxassetid://104991296629094",
		"rbxassetid://133438180299995",
		"rbxassetid://93941773947056",
		"rbxassetid://77986656348925",
		"rbxassetid://78495572122757",
		"rbxassetid://120904976759375",
		"rbxassetid://95419663770597",
		"rbxassetid://87515712746283",
		"rbxassetid://138571839930861",
		"rbxassetid://98368399916607",
	},
	GradeSeals = {
		S = "rbxassetid://134692970944818",
		A = "rbxassetid://121349763981518",
		B = "rbxassetid://137751335648155",
		C = "rbxassetid://121373275704254",
		D = "rbxassetid://119212802355380",
	},
	-- The end of a match's titles in the logo's style (Art/UI/MatchEnd, cut from Art/UI/concepts).
	Victory = "rbxassetid://136548236195039",
	Defeat = "rbxassetid://83527390608420",
	-- The top bar of design 05 (Tools/ui_textures.py): each team's crown, and the score board with the clock's tab.
	HudCrownBlue = "rbxassetid://127147223279087",
	HudCrownRed = "rbxassetid://75076385558157",
	HudScoreboard = "rbxassetid://135647770824642",
	-- The arena from straight above (Play, camera 380 studs up), MAP_REACH studs from the centre to the edge.
	HudMinimap = "rbxassetid://113866338742572",
	-- The spawn pads' rune circle and the ring that sweeps out at a respawn (Tools/pad_textures.py), white to be tinted.
	PadRunes = "rbxassetid://96305253371811",
	PadRing = "rbxassetid://88093541402245",
	-- The match music, a seamless loop (Art/Music/determined_pursuit_loop.wav, uploaded by Tools/upload_audio.py).
	Music = "rbxassetid://97712677913218",
	-- The lobby's music until a match starts, "Ancient God" by Gary Boudreaux (CC BY 4.0, Docs/Third_Party.md), a loop
	-- (Art/Music/ancient_god_loop.wav, uploaded by Tools/upload_audio.py).
	MenuMusic = "rbxassetid://103026116508266",
	-- The buy phase's sounds, Roblox's licensed library (Docs/Third_Party.md): the dark drum sting under "Purchase your
	-- items!", the timpani of the last three seconds, and the deep boom of "FIGHT!".
	BuySting = "rbxassetid://1842178392",
	CountTick = "rbxassetid://1846284931",
	FightBoom = "rbxassetid://9125484526",
	-- The bigger kills' sting (triple kill, shutdown), the first roll of a tribal drum sting from the same library.
	DrumSting = "rbxassetid://1836741188",
	-- The end of a match: a war drum fanfare for the winners, a dark orchestral sting for the losers, from the same
	-- library (picked by the owner on the test ground, 2026-10-28).
	VictorySting = "rbxassetid://1842104084",
	DefeatSting = "rbxassetid://1841258852",
	-- The interface's and the arena's cues (UiSound), from the same library (Docs/Third_Party.md): Roblox's own
	-- interface set, Pro Sound Effects' recordings and an APM boom.
	UiHover = "rbxassetid://10066931761",
	UiSelect = "rbxassetid://10128760939",
	UiSwipe = "rbxassetid://10128766965",
	UiBack = "rbxassetid://10066914500",
	ClothSwing = "rbxassetid://9114369924",
	PaperHandling = "rbxassetid://9125723307",
	ChainMail = "rbxassetid://9113759193",
	CoinJingle = "rbxassetid://9113849492",
	CoinBounce = "rbxassetid://9113848469",
	WoodThud = "rbxassetid://9126267420",
	MagicTwirl = "rbxassetid://9125644310",
	MagicGlow = "rbxassetid://9116394545",
	MagicExit = "rbxassetid://9125635650",
	FallingShimmer = "rbxassetid://9116418035",
	PowerClunk = "rbxassetid://9117885276",
	CorkPull = "rbxassetid://9113944349",
	SwordDraw = "rbxassetid://9119742466",
	EvilBell = "rbxassetid://9114352428",
	CrownDrop = "rbxassetid://9116554603",
	FireWhoosh = "rbxassetid://9114446852",
	FireBurst = "rbxassetid://9114443884",
	RockKnock = "rbxassetid://9118608925",
	RockBreak = "rbxassetid://9118588165",
	GlassShards = "rbxassetid://9114591567",
	DeepThud = "rbxassetid://1843025759",
}
