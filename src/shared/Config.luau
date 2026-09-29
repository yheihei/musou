--!strict
-- ゲームバランス調整用の定数。数値チューニングはこのファイルだけで完結させる。
--
-- 節の足し方
-- 1. 機能ごとに節を1つ足す。節名は CONTEXT.md の語の識別子（ADR 0005）にし、
--    CONTEXT.md に無い機能は英語にする（Stats、Combo など）
-- 2. 節の型を `export type <節名>Section` で公開し、`Config` 型に同じ名前で足す
-- 3. 節の前に見出しのコメントを置き、何に使う値かを書く
-- 4. 値は数値・文字列・真偽値と、それらの表だけにする
--    Color3・Vector3・Enum など Roblox の型は、使う側のモジュールに置く（Lune のテストで読むため）
-- 5. Config.spec.luau は、節の整理で値が変わっていないことを確かめるスナップショットを持つ
--    値を調整したときは、同じ変更でスナップショットも直す

-- キャラクター1人の能力値
export type StatValues = {
	MaxHealth: number,
	Attack: number,
	Defense: number,
	WalkSpeed: number,
	AttackSpeed: number,
}

export type StatsSection = {
	Characters: { [string]: StatValues },
	DefenseHalf: number,
	MinDamage: number,
}

export type ComboSection = {
	ComboResetTime: number,
}

export type OugiSection = {
	PerStock: number,
	MaxStock: number,
	InitialStock: number,
	GainPerHit: number,
	GainPerDamageTaken: number,
	Pulses: number,
	PulseInterval: number,
	Radius: number,
	DamagePerPulse: number,
	Knockback: number,
}

-- 攻撃を受けた側の反応。None は中断しない、Flinch はのけぞり、Knockback は吹き飛び、Launch は打ち上げ
export type Reaction = "None" | "Flinch" | "Knockback" | "Launch"

-- 攻撃判定の形。HitShape.luau の形に直して使う。Kind ごとに使う寸法（スタッド）が違う
-- Box は Range・Width・Height、Sector は Radius・Angle（度）・Height、Sphere は Radius、
-- Line は Length・Width・Speed（スタッド/秒）。Height を省くと Hitbox 節の Height を使う
export type ShapeDef = {
	Kind: "Box" | "Sector" | "Sphere" | "Line",
	Range: number?,
	Width: number?,
	Height: number?,
	Radius: number?,
	Angle: number?,
	Length: number?,
	Speed: number?,
}

-- 技の判定1つ。発生（Startup）から Delay 秒後に出て、Repeat 回を Interval 秒ごとに繰り返す
export type HitDef = {
	Shape: ShapeDef,
	-- 判定の向きを右へ回す角度（度）
	Yaw: number?,
	-- 技の倍率。与ダメージは 倍率 × 攻撃 を、受ける側の防御で軽減したもの
	Power: number,
	Reaction: Reaction,
	-- 吹き飛ばす強さ。軌道の計算ができるまでは、敵にこの大きさの速さを与える
	Knockback: number,
	Delay: number?,
	Repeat: number?,
	Interval: number?,
}

-- 行動1回ぶんのタイムライン（秒）と前進量（スタッド）
export type ActionTimeline = {
	Startup: number,
	Active: number,
	Recovery: number,
	CancelFrom: number,
	Advance: number,
	Interrupt: boolean?,
	-- この行動が終わったときに続けて始める行動
	Next: string?,
	-- 攻撃の判定。攻撃でない行動には無い
	Hits: { HitDef }?,
}

-- 武器種1つぶんの技
export type BukishuDef = {
	-- 通常攻撃の段。1段目から順に並べる
	Attack: { ActionTimeline },
	-- チャージ攻撃。C1 から順に並べる。通常攻撃を n 段出した後は C(n+1) になる
	ChargeKogeki: { ActionTimeline },
}

export type BukishuSection = {
	Shuriken: BukishuDef,
	Katana: BukishuDef,
}

export type ActionSection = {
	BufferTime: number,
	Ougi: ActionTimeline,
	Flinch: ActionTimeline,
	Down: ActionTimeline,
	GetUp: ActionTimeline,
}

export type DamageSection = {
	FlinchImmunity: number,
	GetUpInvulnerable: number,
}

export type HitboxSection = {
	Height: number,
	ShowShapes: boolean,
	ShapeLifetime: number,
}

-- 下忍と上忍で共通の敵の能力値
export type EnemySection = {
	DisplayName: string,
	MaxHealth: number,
	WalkSpeed: number,
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,
	-- 攻撃を受けたプレイヤーの反応
	Reaction: Reaction,
	Scale: number,
}

export type SpawnerSection = {
	MaxAlive: number,
	ButaiSize: number,
	ButaiInterval: number,
	JoninEvery: number,
	MinDistance: number,
	MaxDistance: number,
	AggroRange: number,
	AITickInterval: number,
	CorpseLifetime: number,
}

export type KosenSection = {
	Zensenhaba: number,
	ReserveWeight: number,
	ShikiEffect: number,
	ShikiHoseiMin: number,
	ShikiHoseiMax: number,
	LossRate: number,
	MaxStep: number,
	GunStrength: {
		Mikatagun: number,
		Tekigun: number,
	},
}

export type HikeiSection = {
	Duration: { [string]: number },
}

export type PartySection = {
	MaxMembers: number,
}

export type Config = {
	Party: PartySection,
	Stats: StatsSection,
	Combo: ComboSection,
	Bukishu: BukishuSection,
	Ougi: OugiSection,
	Action: ActionSection,
	Damage: DamageSection,
	Hitbox: HitboxSection,
	Genin: EnemySection,
	Jonin: EnemySection,
	Spawner: SpawnerSection,
	Kosen: KosenSection,
	Hikei: HikeiSection,
}

local Config: Config = {
	-- パーティー。1サーバーが1パーティーにあたる。Roblox のサーバーの最大人数も同じ値にする
	Party = {
		MaxMembers = 4,
	},

	-- 能力値と与ダメージの計算。能力値の補正は Stats.luau が足す
	Stats = {
		-- 操作キャラクターの基本の能力値。キャラクター ID ごとに置く
		-- AttackSpeed は攻撃の速さの倍率で、1 が標準、小さいほど遅い
		Characters = {
			Jin = { MaxHealth = 300, Attack = 12, Defense = 10, WalkSpeed = 24, AttackSpeed = 1 },
			Torika = { MaxHealth = 270, Attack = 11, Defense = 8, WalkSpeed = 26, AttackSpeed = 1.1 },
			Sekishusai = { MaxHealth = 320, Attack = 13, Defense = 12, WalkSpeed = 23, AttackSpeed = 1 },
			-- 金鬼は重く遅い。攻撃の速さを落とし、威力を上げる
			KanaOni = { MaxHealth = 360, Attack = 16, Defense = 14, WalkSpeed = 22, AttackSpeed = 0.8 },
		},
		DefenseHalf = 100, -- 防御がこの値のとき、受けるダメージが半分になる
		MinDamage = 1, -- 与ダメージの下限
	},

	-- 通常攻撃のコンボ。1段ずつ順に出て、前の段のキャンセル受付が始まってから
	-- ComboResetTime 秒以内に次を押すと繋がる。段の中身は Bukishu 節にある
	Combo = {
		ComboResetTime = 0.5,
	},

	-- 武器種ごとの技（通常攻撃6段とチャージ攻撃 C1〜C6）。同じ武器種のキャラクターで共有する（ADR 0004）。
	-- 行動のタイムラインに判定（Hits）を足したもの。時間はキャラクターの攻撃の速さ（Stats 節の AttackSpeed）で割る
	Bukishu = {
		-- 手裏剣セット（刃・酉花）。近くを斬り、ときどき手裏剣を投げる
		Shuriken = {
			Attack = {
				-- 1段目 斬り払い
				{
					Startup = 0.05,
					Active = 0.08,
					Recovery = 0.17,
					CancelFrom = 0.26,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 7, Width = 8 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 2段目 斬り返し
				{
					Startup = 0.05,
					Active = 0.08,
					Recovery = 0.17,
					CancelFrom = 0.26,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 7, Width = 8 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 3段目 手裏剣を1枚投げる
				{
					Startup = 0.08,
					Active = 0.1,
					Recovery = 0.17,
					CancelFrom = 0.3,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 30, Width = 3, Speed = 120 },
							Power = 0.9,
							Reaction = "Flinch",
							Knockback = 6,
						},
					},
				},
				-- 4段目 回し蹴り
				{
					Startup = 0.06,
					Active = 0.1,
					Recovery = 0.2,
					CancelFrom = 0.32,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 8, Angle = 180 },
							Power = 1.1,
							Reaction = "Flinch",
							Knockback = 10,
						},
					},
				},
				-- 5段目 手裏剣を3枚、扇に投げる
				{
					Startup = 0.08,
					Active = 0.1,
					Recovery = 0.22,
					CancelFrom = 0.36,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 28, Width = 3, Speed = 120 },
							Yaw = -15,
							Power = 0.8,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 28, Width = 3, Speed = 120 },
							Power = 0.8,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 28, Width = 3, Speed = 120 },
							Yaw = 15,
							Power = 0.8,
							Reaction = "Flinch",
							Knockback = 6,
						},
					},
				},
				-- 6段目 宙返りして周りを斬る。締めで吹き飛ばす
				{
					Startup = 0.12,
					Active = 0.12,
					Recovery = 0.46,
					CancelFrom = 0.68,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Sphere", Radius = 9 },
							Power = 2.2,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
			},
			ChargeKogeki = {
				-- C1 踏み込んで蹴り飛ばす
				{
					Startup = 0.18,
					Active = 0.1,
					Recovery = 0.42,
					CancelFrom = 0.7,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 9, Width = 8 },
							Power = 2,
							Reaction = "Knockback",
							Knockback = 40,
						},
					},
				},
				-- C2 蹴り上げて打ち上げる
				{
					Startup = 0.14,
					Active = 0.1,
					Recovery = 0.46,
					CancelFrom = 0.7,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 8, Angle = 120 },
							Power = 1.6,
							Reaction = "Launch",
							Knockback = 50,
						},
					},
				},
				-- C3 蹴り上げてから跳んで追い打ちする
				{
					Startup = 0.14,
					Active = 0.5,
					Recovery = 0.4,
					CancelFrom = 1.04,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 8 },
							Power = 1.2,
							Reaction = "Launch",
							Knockback = 45,
						},
						{
							Shape = { Kind = "Box", Range = 10, Width = 8, Height = 18 },
							Delay = 0.12,
							Repeat = 3,
							Interval = 0.12,
							Power = 0.5,
							Reaction = "Launch",
							Knockback = 20,
						},
					},
				},
				-- C4 煙玉を炸裂させて周りを吹き飛ばす
				{
					Startup = 0.2,
					Active = 0.1,
					Recovery = 0.5,
					CancelFrom = 0.8,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Sphere", Radius = 11 },
							Power = 1.8,
							Reaction = "Knockback",
							Knockback = 55,
						},
					},
				},
				-- C5 八方へ手裏剣を3回撒く
				{
					Startup = 0.12,
					Active = 0.45,
					Recovery = 0.4,
					CancelFrom = 0.97,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 0,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 45,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 90,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 135,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 180,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 225,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 270,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
						{
							Shape = { Kind = "Line", Length = 26, Width = 3, Speed = 120 },
							Yaw = 315,
							Repeat = 3,
							Interval = 0.15,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 6,
						},
					},
				},
				-- C6 手裏剣の雨を前へ浴びせ、最後に周りを吹き飛ばす
				{
					Startup = 0.15,
					Active = 0.6,
					Recovery = 0.55,
					CancelFrom = 1.3,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = -30,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = -15,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = 0,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = 15,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Line", Length = 34, Width = 3, Speed = 120 },
							Yaw = 30,
							Repeat = 3,
							Interval = 0.1,
							Power = 0.7,
							Reaction = "Flinch",
							Knockback = 8,
						},
						{
							Shape = { Kind = "Sphere", Radius = 12 },
							Delay = 0.5,
							Power = 3,
							Reaction = "Knockback",
							Knockback = 60,
						},
					},
				},
			},
		},
		-- 刀セット（石舟斎・金鬼）。前方の箱と扇で斬る。金鬼の重さは攻撃の速さで出す
		Katana = {
			Attack = {
				-- 1段目 袈裟斬り
				{
					Startup = 0.06,
					Active = 0.08,
					Recovery = 0.2,
					CancelFrom = 0.3,
					Advance = 1.5,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 8 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 2段目 逆袈裟
				{
					Startup = 0.06,
					Active = 0.08,
					Recovery = 0.2,
					CancelFrom = 0.3,
					Advance = 1.5,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 9 },
							Power = 1,
							Reaction = "Flinch",
							Knockback = 8,
						},
					},
				},
				-- 3段目 横薙ぎ
				{
					Startup = 0.08,
					Active = 0.1,
					Recovery = 0.22,
					CancelFrom = 0.34,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 9, Angle = 140 },
							Power = 1.1,
							Reaction = "Flinch",
							Knockback = 10,
						},
					},
				},
				-- 4段目 踏み込んで突く
				{
					Startup = 0.1,
					Active = 0.08,
					Recovery = 0.24,
					CancelFrom = 0.36,
					Advance = 3,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 12, Width = 4 },
							Power = 1.2,
							Reaction = "Flinch",
							Knockback = 12,
						},
					},
				},
				-- 5段目 回転斬り
				{
					Startup = 0.08,
					Active = 0.12,
					Recovery = 0.24,
					CancelFrom = 0.4,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 9, Angle = 360 },
							Power = 1.2,
							Reaction = "Flinch",
							Knockback = 12,
						},
					},
				},
				-- 6段目 唐竹割り。締めで吹き飛ばす
				{
					Startup = 0.14,
					Active = 0.1,
					Recovery = 0.5,
					CancelFrom = 0.72,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 10, Width = 10 },
							Power = 2.4,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
			},
			ChargeKogeki = {
				-- C1 溜めてから突進して斬る
				{
					Startup = 0.2,
					Active = 0.1,
					Recovery = 0.45,
					CancelFrom = 0.75,
					Advance = 4,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 11, Width = 6 },
							Power = 2.2,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
				-- C2 斬り上げて打ち上げる
				{
					Startup = 0.15,
					Active = 0.1,
					Recovery = 0.5,
					CancelFrom = 0.75,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 9, Angle = 100 },
							Power = 1.7,
							Reaction = "Launch",
							Knockback = 55,
						},
					},
				},
				-- C3 斬り上げてから跳んで追い打ち
				{
					Startup = 0.14,
					Active = 0.5,
					Recovery = 0.4,
					CancelFrom = 1.04,
					Advance = 1,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 8, Width = 8 },
							Power = 1.3,
							Reaction = "Launch",
							Knockback = 45,
						},
						{
							Shape = { Kind = "Box", Range = 9, Width = 9, Height = 18 },
							Delay = 0.12,
							Repeat = 3,
							Interval = 0.12,
							Power = 0.5,
							Reaction = "Launch",
							Knockback = 20,
						},
					},
				},
				-- C4 回転斬りで周りを吹き飛ばす
				{
					Startup = 0.2,
					Active = 0.12,
					Recovery = 0.5,
					CancelFrom = 0.82,
					Advance = 0,
					Hits = {
						{
							Shape = { Kind = "Sector", Radius = 11, Angle = 360 },
							Power = 1.9,
							Reaction = "Knockback",
							Knockback = 55,
						},
					},
				},
				-- C5 乱れ斬りの後に斬り払う
				{
					Startup = 0.12,
					Active = 0.6,
					Recovery = 0.4,
					CancelFrom = 1.12,
					Advance = 2,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 10, Width = 10 },
							Repeat = 5,
							Interval = 0.1,
							Power = 0.5,
							Reaction = "Flinch",
							Knockback = 5,
						},
						{
							Shape = { Kind = "Box", Range = 10, Width = 10 },
							Delay = 0.55,
							Power = 1.4,
							Reaction = "Knockback",
							Knockback = 45,
						},
					},
				},
				-- C6 大上段から斬り下ろし、衝撃波で周りも吹き飛ばす
				{
					Startup = 0.3,
					Active = 0.2,
					Recovery = 0.6,
					CancelFrom = 1.1,
					Advance = 3,
					Hits = {
						{
							Shape = { Kind = "Box", Range = 14, Width = 12 },
							Power = 3.2,
							Reaction = "Knockback",
							Knockback = 65,
						},
						{
							Shape = { Kind = "Sphere", Radius = 13 },
							Delay = 0.1,
							Power = 1.5,
							Reaction = "Knockback",
							Knockback = 50,
						},
					},
				},
			},
		},
	},

	-- 奥義（Q）と奥義ゲージ。ストック1本で1回発動する。本数の計算は OugiGauge.luau にある
	Ougi = {
		PerStock = 100, -- 1本分の量
		MaxStock = 4, -- 本数の上限
		InitialStock = 1, -- 最初に持っている本数
		GainPerHit = 2,
		GainPerDamageTaken = 0.5,
		Pulses = 6,
		PulseInterval = 0.2,
		Radius = 18,
		DamagePerPulse = 40,
		Knockback = 30,
	},

	-- 行動のタイムライン。状態遷移は ActionState.luau が計算する
	-- Startup は判定が出るまで、Active は判定が出ている間、Recovery はその後の硬直の秒数。
	-- 開始から CancelFrom 秒たつと次の行動を受け付ける。Advance は発生と持続の間に前へ進む量。
	-- Interrupt の行動は、受付の前でも今の行動に割り込める。通常攻撃とチャージ攻撃は Bukishu 節にある
	Action = {
		BufferTime = 0.4, -- 受け付けられなかった入力を先行入力として持っておく秒数
		-- 持続は Ougi.Pulses × Ougi.PulseInterval と同じにする
		Ougi = { Startup = 0, Active = 1.2, Recovery = 0, CancelFrom = 1.2, Advance = 0, Interrupt = true },
		-- 被弾の反応。吹き飛びと打ち上げはダウンにし、ダウンの後は起き上がりを続ける
		Flinch = { Startup = 0, Active = 0, Recovery = 0.35, CancelFrom = 0.35, Advance = 0 },
		Down = { Startup = 0, Active = 0, Recovery = 0.8, CancelFrom = 0.8, Advance = 0, Next = "GetUp" },
		GetUp = { Startup = 0, Active = 0, Recovery = 0.5, CancelFrom = 0.5, Advance = 0 },
	},

	-- プレイヤーの被ダメージ。無敵・反応・防御の軽減の判定は Damage.luau が計算する
	Damage = {
		FlinchImmunity = 1, -- のけぞりが明けてから、次の攻撃でのけぞらない秒数（囲まれての連続ののけぞりを防ぐ）
		GetUpInvulnerable = 0.8, -- 起き上がった後の無敵の秒数。ダウンと起き上がりの間も無敵
	},

	-- 攻撃判定の形。形の計算は HitShape.luau にある
	Hitbox = {
		Height = 8, -- 通常攻撃の箱の高さ（スタッド）
		ShowShapes = false, -- 判定の形をデバッグ表示するか。窓口の ShowHitbox でも切り替えられる
		ShapeLifetime = 0.3, -- デバッグ表示を残す秒数
	},

	-- 下忍。色は EnemyService に置く
	Genin = {
		DisplayName = "下忍",
		MaxHealth = 30,
		WalkSpeed = 12,
		Damage = 6,
		AttackRange = 4.5,
		AttackCooldown = 1.5,
		Reaction = "Flinch",
		Scale = 1,
	},

	-- 上忍。色は EnemyService に置く
	Jonin = {
		DisplayName = "上忍",
		MaxHealth = 600,
		WalkSpeed = 14,
		Damage = 20,
		AttackRange = 6,
		AttackCooldown = 1.8,
		Reaction = "Knockback",
		Scale = 1.4,
	},

	-- 暫定の湧き処理。実体化圏での出し入れができたら置き換える
	Spawner = {
		MaxAlive = 40,
		ButaiSize = 8,
		ButaiInterval = 3,
		JoninEvery = 5, -- 何部隊ごとに上忍を出すか
		MinDistance = 60,
		MaxDistance = 140,
		AggroRange = 80,
		AITickInterval = 0.25,
		CorpseLifetime = 2,
	},

	-- 交戦。部隊どうしの押し合いの損害を Kosen.luau で計算する
	Kosen = {
		Zensenhaba = 10, -- 一度に刃を交えられる兵数の上限
		ReserveWeight = 0.3, -- 前線の後ろに控える兵1人が押す力に加わる割合
		ShikiEffect = 0.01, -- 士気の差 1 あたりの押す力の増減の割合
		ShikiHoseiMin = 0.3, -- 士気の差による押す力の倍率の下限
		ShikiHoseiMax = 2, -- 士気の差による押す力の倍率の上限
		LossRate = 0.02, -- 押す力 1 が相手に与える 1 秒あたりの損害（兵数）
		MaxStep = 0.5, -- 1 回に進める時間の上限（秒）。長い経過時間はこの幅に刻んで計算する
		-- 軍ごとの強さの倍率。味方軍は敵軍よりやや弱くする
		GunStrength = {
			Mikatagun = 0.9,
			Tekigun = 1,
		},
	},

	-- 秘計。持ち込みの上限枚数はボタンの数に合わせた仕様値なので Hikei.luau に置く
	Hikei = {
		-- 効果時間（秒）。ここに無い秘計の効果は期限なし（兵糧庫と爆破罠は拠点を失うまで残る）
		Duration = {
			Fukuhei = 120, -- 伏兵部隊が潜んでいられる時間
			Rakuseki = 90, -- 岩が道を塞いでいる時間
			Chohatsu = 15, -- 相手の上忍を誘い出す時間
			Kishinka = 60,
			Daikatsu = 30, -- 動揺させる時間
		},
	},
}

return Config
