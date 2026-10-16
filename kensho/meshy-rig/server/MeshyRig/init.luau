--!strict
-- #16 の検証用プレースの道具。Meshy のリグ（骨）と R15 のあいだで、Adaptive Animation による往復の再生を確かめる。
-- テストプレイ（F5）か実行（F8）の間に、コマンドバー（サーバー表示）から呼ぶ。musou のプレースには入れない。
--
--   local MeshyRig = require(game.ServerStorage.MeshyRig)
--   print(MeshyRig.demo())               -- 合成した刃の骨と R15 を並べ、往路と復路を 6 秒ずつ交互に流す
--   print(MeshyRig.orai())               -- 往路。R15 のモーション（Ninja の待機と走り）を刃の骨で流し、手足の向きを R15 と比べる
--   print(MeshyRig.fukuro())             -- 復路。刃の攻撃（Meshy のクリップ id004）を R15 で流し、手足の向きを刃の骨と比べる
--   print(MeshyRig.fukuro(nil, "id219"))  -- 復路を Jin.luau のほかのクリップで（下忍の6項目は 219・179・182・007・189・003）
--   print(MeshyRig.map(workspace.Jin))   -- 取り込んだモデルの 22 関節を、骨の名前で HumanoidRigDescription に対応づける
--   print(MeshyRig.orai(workspace.Jin))  -- 取り込んだモデルで往路
--   print(MeshyRig.fukuro(workspace.Jin))  -- 取り込んだモデルで復路（クリップ編集で読み込んだクリップを使う）
--   print(MeshyRig.hikaku("Knockback"))  -- #88。下忍の項目を、原本と腰の移動を抜いた版の R15 で、ゲームの体の扱いと時間どおりに比べる
--   print(MeshyRig.hikaku("Down", nil, { Down = "pose" }))  -- 抜き方を差し替えて比べる（xz・all・pose）
--   print(MeshyRig.clear())
--
-- 分かっていること（2026-10-16、musou のテストプレイで合成した骨で確かめた）
-- - 骨のモデルに HumanoidRigDescription があれば、公開済みの R15 のモーションが骨へ移る（AnimationController でも Humanoid でも同じ）
-- - 体の正面は、根元の部品（骨の親の部品）の -Z として扱われる。根元の部品だけを回すと脚が後ろへ曲がる
-- - 骨の名前のクリップは、HumanoidRigDescription の有無によらず骨にそのまま効く。R15 には効かない
-- - クリップに AnimationRigData（AnimationRigData:LoadFromModel で骨のモデルから作る）を付けると、R15 に移る
-- - 公開済みの R15 のモーションには、元の体の AnimationRigData（AnimationRigDataBlocky）が入っている
-- - KeyframeSequenceProvider:RegisterKeyframeSequence の一時 ID でも、AnimationRigData があれば移る（公開しなくてよい）
-- - トラックを止めても骨の姿勢は残る（次のトラックが流れると戻る）

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Jin = require(script:WaitForChild("Jin"))

local MeshyRig = {}

-- HumanoidRigDescription の関節と、Meshy のリグの骨の名前（Meshy の骨は 24 本で、22 関節すべてが埋まる）
MeshyRig.JOINTS = {
	Root = "Hips",
	Waist = "Spine02",
	Spine = "Spine01",
	Chest = "Spine",
	Neck = "neck",
	HeadBase = "Head",
	LeftClavicle = "LeftShoulder",
	LeftShoulder = "LeftArm",
	LeftElbow = "LeftForeArm",
	LeftWrist = "LeftHand",
	RightClavicle = "RightShoulder",
	RightShoulder = "RightArm",
	RightElbow = "RightForeArm",
	RightWrist = "RightHand",
	LeftHip = "LeftUpLeg",
	LeftKnee = "LeftLeg",
	LeftAnkle = "LeftFoot",
	LeftToeBase = "LeftToeBase",
	RightHip = "RightUpLeg",
	RightKnee = "RightLeg",
	RightAnkle = "RightFoot",
	RightToeBase = "RightToeBase",
} :: { [string]: string }

-- R15 の関節の位置は、部品の RigAttachment で読む
local R15_ATTACHMENTS: { [string]: { string } } = {
	Root = { "LowerTorso", "RootRigAttachment" },
	Neck = { "Head", "NeckRigAttachment" },
	LeftShoulder = { "LeftUpperArm", "LeftShoulderRigAttachment" },
	LeftElbow = { "LeftLowerArm", "LeftElbowRigAttachment" },
	LeftWrist = { "LeftHand", "LeftWristRigAttachment" },
	RightShoulder = { "RightUpperArm", "RightShoulderRigAttachment" },
	RightElbow = { "RightLowerArm", "RightElbowRigAttachment" },
	RightWrist = { "RightHand", "RightWristRigAttachment" },
	LeftHip = { "LeftUpperLeg", "LeftHipRigAttachment" },
	LeftKnee = { "LeftLowerLeg", "LeftKneeRigAttachment" },
	LeftAnkle = { "LeftFoot", "LeftAnkleRigAttachment" },
	RightHip = { "RightUpperLeg", "RightHipRigAttachment" },
	RightKnee = { "RightLowerLeg", "RightKneeRigAttachment" },
	RightAnkle = { "RightFoot", "RightAnkleRigAttachment" },
}

-- 比べる手足（関節から関節への向き）
local SEGMENTS: { { string } } = {
	{ "胴", "Root", "Neck" },
	{ "左上腕", "LeftShoulder", "LeftElbow" },
	{ "左前腕", "LeftElbow", "LeftWrist" },
	{ "右上腕", "RightShoulder", "RightElbow" },
	{ "右前腕", "RightElbow", "RightWrist" },
	{ "左太もも", "LeftHip", "LeftKnee" },
	{ "左すね", "LeftKnee", "LeftAnkle" },
	{ "右太もも", "RightHip", "RightKnee" },
	{ "右すね", "RightKnee", "RightAnkle" },
}

-- 往路で流す R15 のモーション（Ninja アニメーションパッケージ。src/shared/Motions.luau と同じ ID）
MeshyRig.R15_ANIMATIONS = {
	{ id = 10921155160, name = "Ninja の待機" },
	{ id = 10921157929, name = "Ninja の走り" },
}

local FOLDER_NAME = "MeshyRigCheck"
local SAMPLES = 5
local SETTLE = 0.5

local state = {
	sticks = nil :: RBXScriptConnection?,
	demoToken = 0,
}

local function folder(): Folder
	local found = workspace:FindFirstChild(FOLDER_NAME)
	if found and found:IsA("Folder") then
		return found
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	return created
end

local function findBone(model: Instance, name: string): Bone?
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("Bone") then
		return found
	end
	return nil
end

-- 骨の親をたどって、根元の部品を返す
local function rootPartOf(bone: Instance): BasePart?
	local current: Instance? = bone.Parent
	while current do
		if current:IsA("BasePart") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isR15(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil
		and humanoid.RigType == Enum.HumanoidRigType.R15
		and model:FindFirstChild("LowerTorso") ~= nil
end

local function animatorOf(model: Model): Animator
	local controller: Instance? = model:FindFirstChildOfClass("Humanoid")
		or model:FindFirstChildOfClass("AnimationController")
	if not controller then
		local created = Instance.new("AnimationController")
		created.Parent = model
		controller = created
	end
	assert(controller, "AnimationController が無い")
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	return animator :: Animator
end

-- 関節の位置（ワールド）と、比べるときの基準の部品
local function jointPositions(model: Model): ({ [string]: Vector3 }, BasePart)
	local positions = {}
	if isR15(model) then
		for joint, where in R15_ATTACHMENTS do
			local part = model:FindFirstChild(where[1])
			local attachment = part and part:FindFirstChild(where[2])
			assert(attachment and attachment:IsA("Attachment"), `{model.Name} に {where[1]}.{where[2]} が無い`)
			positions[joint] = attachment.WorldPosition
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		assert(root and root:IsA("BasePart"), `{model.Name} に HumanoidRootPart が無い`)
		return positions, root
	end
	local description = model:FindFirstChildOfClass("HumanoidRigDescription")
	assert(description, `{model.Name} に HumanoidRigDescription が無い（先に MeshyRig.map で対応づける）`)
	for joint in R15_ATTACHMENTS do
		local bone = (description :: any)[joint]
		assert(bone and bone:IsA("Bone"), `{model.Name} の関節 {joint} が対応づいていない`)
		positions[joint] = bone.TransformedWorldCFrame.Position
	end
	local hips = (description :: any).Root
	local root = rootPartOf(hips)
	assert(root, `{model.Name} の骨の根元の部品が無い`)
	return positions, root
end

-- 手足の向き（基準の部品から見た向き。置き場所と向きによらず比べられる）
local function directions(model: Model): { [string]: Vector3 }
	local positions, root = jointPositions(model)
	local result = {}
	for _, segment in SEGMENTS do
		local world = positions[segment[3]] - positions[segment[2]]
		result[segment[1]] = root.CFrame:VectorToObjectSpace(world).Unit
	end
	return result
end

local function angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- 合成した骨を棒で見せる（骨の位置を毎フレーム部品に写す）
local function startSticks()
	if state.sticks then
		return
	end
	state.sticks = RunService.Heartbeat:Connect(function()
		local root = workspace:FindFirstChild(FOLDER_NAME)
		if not root then
			return
		end
		for _, stick in root:GetDescendants() do
			if stick:IsA("BasePart") and stick:GetAttribute("StickFrom") then
				local model = stick:FindFirstAncestorOfClass("Model")
				local from = model and findBone(model, stick:GetAttribute("StickFrom") :: string)
				local to = model and findBone(model, stick:GetAttribute("StickTo") :: string)
				if from and to then
					local p0 = from.TransformedWorldCFrame.Position
					local p1 = to.TransformedWorldCFrame.Position
					local length = (p1 - p0).Magnitude
					if length > 0.01 then
						stick.Size = Vector3.new(stick.Size.X, stick.Size.Y, length)
						stick.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
					end
				end
			end
		end
	end)
end

-- HumanoidRigDescription を作り（あれば使い）、22 関節を骨の名前で対応づける。報告の文字列を返す
function MeshyRig.map(model: Model): string
	assert(typeof(model) == "Instance" and model:IsA("Model"), "モデルを渡す（例: workspace.Jin）")
	local description = model:FindFirstChildOfClass("HumanoidRigDescription")
	if not description then
		description = Instance.new("HumanoidRigDescription")
		description.Parent = model
	end
	assert(description, "HumanoidRigDescription を作れない")
	-- 関節のプロパティ（Root・Waist など）は名前で書くので any で扱う
	local joints: any = description
	local missing = {}
	local count = 0
	for joint, boneName in MeshyRig.JOINTS do
		local bone = findBone(model, boneName)
		if bone then
			joints[joint] = bone
			count += 1
		else
			table.insert(missing, `{joint}（{boneName}）`)
		end
	end
	table.sort(missing)
	animatorOf(model)
	local lines = {
		`{model.Name} の関節を {count}/22 対応づけた（足りない骨: {if #missing > 0
			then table.concat(missing, "、")
			else "なし"}）`,
	}
	-- 体の正面（Head から headfront への向き）が、根元の部品の -Z からどれだけずれているか
	local head = findBone(model, "Head")
	local front = findBone(model, "headfront")
	local hips = findBone(model, "Hips")
	local root = hips and rootPartOf(hips)
	if head and front and root then
		local localDir = root.CFrame:VectorToObjectSpace(
			front.TransformedWorldCFrame.Position - head.TransformedWorldCFrame.Position
		)
		local flat = Vector3.new(localDir.X, 0, localDir.Z)
		if flat.Magnitude > 0.001 then
			local off = angleBetween(flat.Unit, Vector3.new(0, 0, -1))
			table.insert(
				lines,
				`体の正面は、根元の部品 {root.Name} の -Z から {string.format("%.0f", off)} 度（45 度を超えると往路の脚が崩れる）`
			)
		end
	end
	return table.concat(lines, "\n")
end

-- 合成した刃の骨（Jin.luau）を組む。根元の部品の -Z が正面
function MeshyRig.buildJin(cframe: CFrame?): Model
	local model = Instance.new("Model")
	model.Name = "JinBones"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Size = Vector3.new(1, 0.2, 1)
	root.Transparency = 0.5
	root.CFrame = cframe or CFrame.new(-4, 0.1, -12)
	root.Parent = model
	model.PrimaryPart = root
	local bones: { [string]: Bone } = {}
	for _, row in Jin.bones do
		local bone = Instance.new("Bone")
		bone.Name = row[1]
		bone.CFrame = CFrame.new(row[3], row[4], row[5], row[6], row[7], row[8], row[9])
		bone.Parent = if row[2] == "" then root else bones[row[2]]
		bones[row[1]] = bone
		if row[2] ~= "" then
			local stick = Instance.new("Part")
			stick.Name = `Stick_{row[1]}`
			stick.Anchored = true
			stick.CanCollide = false
			stick.CanQuery = false
			stick.CanTouch = false
			stick.Size = Vector3.new(0.18, 0.18, 0.5)
			stick.Material = Enum.Material.SmoothPlastic
			stick.Color = if row[1] == "headfront" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(40, 60, 130)
			stick:SetAttribute("StickFrom", row[2])
			stick:SetAttribute("StickTo", row[1])
			stick.Parent = model
		end
	end
	model.Parent = folder()
	MeshyRig.map(model)
	startSticks()
	return model
end

-- R15 の見本（既定の体）を組む。HumanoidRootPart は固定する
function MeshyRig.buildR15(cframe: CFrame?): Model
	local model =
		Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = "R15"
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local height = humanoid.HipHeight + root.Size.Y / 2
	model:PivotTo(cframe or CFrame.new(4, height, -12))
	model.Parent = folder()
	animatorOf(model)
	return model
end

local function findOrBuild(name: string, build: () -> Model): Model
	local found = folder():FindFirstChild(name)
	if found and found:IsA("Model") then
		return found
	end
	return build()
end

local function stopAll(model: Model)
	for _, track in animatorOf(model):GetPlayingAnimationTracks() do
		track:Stop(0)
	end
end

local function play(model: Model, animationId: string): AnimationTrack
	stopAll(model)
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local track = animatorOf(model):LoadAnimation(animation)
	track.Looped = true
	track:Play(0)
	return track
end

local function waitLength(track: AnimationTrack)
	local waited = 0
	while track.Length == 0 and waited < 3 do
		waited += task.wait(0.1)
	end
end

type Stat = { sum: number, max: number }

-- reference と subject に同じ時刻の姿勢を取らせ、subject の手足の向きの reference との差を測る
local function measure(
	reference: Model,
	referenceTrack: AnimationTrack,
	subject: Model,
	subjectTrack: AnimationTrack
): string
	waitLength(referenceTrack)
	waitLength(subjectTrack)
	local length = referenceTrack.Length
	local stats: { [string]: Stat } = {}
	local first: { [string]: Vector3 }? = nil
	local moved = 0
	for index = 1, SAMPLES do
		local position = length * (index - 0.5) / SAMPLES
		for _, track in { referenceTrack, subjectTrack } do
			track.TimePosition = position
			track:AdjustSpeed(0)
		end
		task.wait(SETTLE)
		local ref = directions(reference)
		local sub = directions(subject)
		if not first then
			first = ref
		end
		for _, segment in SEGMENTS do
			local name = segment[1]
			local diff = angleBetween(ref[name], sub[name])
			local stat = stats[name] or { sum = 0, max = 0 }
			stat.sum += diff
			stat.max = math.max(stat.max, diff)
			stats[name] = stat
			moved = math.max(moved, angleBetween((first :: any)[name], ref[name]))
		end
	end
	for _, track in { referenceTrack, subjectTrack } do
		track:AdjustSpeed(1)
	end
	local parts = {}
	local overall = 0
	for _, segment in SEGMENTS do
		local stat = stats[segment[1]]
		overall = math.max(overall, stat.max)
		table.insert(parts, string.format("%s %.0f/%.0f", segment[1], stat.sum / SAMPLES, stat.max))
	end
	return string.format(
		"%.2f 秒、%s の手足は最大 %.0f 度動く。差の最大 %.0f 度（平均/最大: %s）",
		length,
		reference.Name,
		moved,
		overall,
		table.concat(parts, "、")
	)
end

-- 往路。R15 のモーションを骨のモデルで流し、手足の向きを R15 と比べる
function MeshyRig.orai(target: Model?): string
	-- 見本の再生を止める（測っている間にモーションが切り替わらないように）
	state.demoToken += 1
	local r15 = findOrBuild("R15", MeshyRig.buildR15)
	local subject = target or findOrBuild("JinBones", MeshyRig.buildJin)
	if not subject:FindFirstChildOfClass("HumanoidRigDescription") then
		MeshyRig.map(subject)
	end
	local lines =
		{ `往路（R15 のモーションを {subject.Name} で流す。手足の向きの R15 との差）` }
	for _, entry in MeshyRig.R15_ANIMATIONS do
		local id = `rbxassetid://{entry.id}`
		local referenceTrack = play(r15, id)
		local subjectTrack = play(subject, id)
		table.insert(lines, `- {entry.name}（{entry.id}）: {measure(r15, referenceTrack, subject, subjectTrack)}`)
	end
	return table.concat(lines, "\n")
end

-- Jin.luau のクリップから、骨の名前の KeyframeSequence を作る
local function clipToKeyframeSequence(clipName: string): KeyframeSequence
	local clip = Jin.clips[clipName]
	assert(clip, `Jin.luau にクリップ {clipName} が無い`)
	local parentOf: { [string]: string } = {}
	for _, row in Jin.bones do
		parentOf[row[1]] = row[2]
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = `{clipName}_{clip.name}`
	sequence.Loop = false
	sequence.Priority = Enum.AnimationPriority.Action
	for _, line in clip.frames do
		local values = string.split(line, ",")
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = tonumber(values[1]) :: number
		local rootPose = Instance.new("Pose")
		rootPose.Name = "Root"
		rootPose.Weight = 0
		rootPose.Parent = keyframe
		local poses: { [string]: Pose } = {}
		for index, boneName in clip.order do
			local base = 1 + (index - 1) * 7
			local n = function(offset: number): number
				return tonumber(values[base + offset]) :: number
			end
			local pose = Instance.new("Pose")
			pose.Name = boneName
			pose.Weight = 1
			pose.CFrame = CFrame.new(n(1), n(2), n(3), n(4), n(5), n(6), n(7))
			poses[boneName] = pose
		end
		for boneName, pose in poses do
			local parentName = parentOf[boneName]
			pose.Parent = if parentName == "" or poses[parentName] == nil then rootPose else poses[parentName]
		end
		keyframe.Parent = sequence
	end
	return sequence
end

-- 骨のモデル（HumanoidRigDescription つき）から AnimationRigData を作る。LoadFromModel は型の定義に無いので any で呼ぶ
local function rigDataFor(model: Model): Instance
	local rigData: any = Instance.new("AnimationRigData")
	rigData.Name = `AnimationRigData{model.Name}`
	rigData:LoadFromModel(model)
	return rigData
end

local function withoutRigData(sequence: KeyframeSequence): KeyframeSequence
	local copy = sequence:Clone()
	for _, child in copy:GetChildren() do
		if child:IsA("AnimationRigData") then
			child:Destroy()
		end
	end
	return copy
end

-- クリップ編集で読み込んだクリップ（ServerStorage.RBX_ANIMSAVES.<モデルの名前>）のうち、いちばん長いものを返す
-- 取り込みのときにできる1コマだけの clip0 を選ばないように、長さで選ぶ
function MeshyRig.savedClip(model: Model): KeyframeSequence?
	local saves = game:GetService("ServerStorage"):FindFirstChild("RBX_ANIMSAVES")
	local holder = saves and saves:FindFirstChild(model.Name)
	if not holder then
		return nil
	end
	local best: KeyframeSequence? = nil
	local bestLength = 0
	for _, child in holder:GetDescendants() do
		if child:IsA("KeyframeSequence") then
			local length = 0
			for _, keyframe in child:GetChildren() do
				if keyframe:IsA("Keyframe") then
					length = math.max(length, keyframe.Time)
				end
			end
			if length > bestLength then
				best = child
				bestLength = length
			end
		end
	end
	return best
end

-- 復路。Meshy のクリップを骨のモデルでそのまま流し、AnimationRigData を付けた同じクリップを R15 で流して比べる
-- sequence を渡さなければ、クリップ編集で読み込んだクリップ（MeshyRig.savedClip）を使う。それも無ければ Jin.luau の id004（刃の攻撃）
-- sequence に文字列を渡すと、Jin.luau のその名前のクリップ（"id219" など）を使う
-- Jin.luau の値は GLB の休息の姿勢からの差なので、取り込んだ FBX の骨の向きが GLB と違うと崩れる（見た目で確かめる）
function MeshyRig.fukuro(target: Model?, sequence: (KeyframeSequence | string)?): string
	-- 見本の再生を止める（測っている間にモーションが切り替わらないように）
	state.demoToken += 1
	local r15 = findOrBuild("R15", MeshyRig.buildR15)
	local subject = target or findOrBuild("JinBones", MeshyRig.buildJin)
	if not subject:FindFirstChildOfClass("HumanoidRigDescription") then
		MeshyRig.map(subject)
	end
	local source = if type(sequence) == "string"
		then clipToKeyframeSequence(sequence)
		else (sequence :: KeyframeSequence?) or MeshyRig.savedClip(subject) or clipToKeyframeSequence("id004")
	local plain = withoutRigData(source)
	local rigged = withoutRigData(source)
	rigDataFor(subject).Parent = rigged
	local plainId = KeyframeSequenceProvider:RegisterKeyframeSequence(plain)
	local riggedId = KeyframeSequenceProvider:RegisterKeyframeSequence(rigged)
	local subjectTrack = play(subject, plainId)
	local referenceTrack = play(r15, riggedId)
	local result = measure(subject, subjectTrack, r15, referenceTrack)
	return `復路（{source.Name} を R15 で流す。R15 の手足の向きの {subject.Name} との差）\n- {result}`
end

-- 合成した刃の骨と R15 を並べ、往路（Ninja の走り）と復路（刃の攻撃）を 6 秒ずつ交互に流す
function MeshyRig.demo(): string
	MeshyRig.clear()
	state.demoToken += 1
	local token = state.demoToken
	local facing = CFrame.Angles(0, math.pi, 0)
	local jin = MeshyRig.buildJin(CFrame.new(-4, 0.1, -12) * facing)
	local r15 = MeshyRig.buildR15()
	local humanoid = r15:FindFirstChildOfClass("Humanoid") :: Humanoid
	local rootPart = r15:FindFirstChild("HumanoidRootPart") :: BasePart
	r15:PivotTo(CFrame.new(4, humanoid.HipHeight + rootPart.Size.Y / 2, -12) * facing)
	local label = Instance.new("Part")
	label.Name = "Label"
	label.Anchored = true
	label.CanCollide = false
	label.CanQuery = false
	label.CanTouch = false
	label.Transparency = 1
	label.Size = Vector3.new(1, 1, 1)
	label.Position = Vector3.new(0, 8, -12)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 60)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 0.3
	text.TextScaled = true
	text.Parent = gui
	gui.Parent = label
	label.Parent = folder()
	local rigged = clipToKeyframeSequence("id004")
	rigDataFor(jin).Parent = rigged
	local attackPlain = KeyframeSequenceProvider:RegisterKeyframeSequence(clipToKeyframeSequence("id004"))
	local attackRigged = KeyframeSequenceProvider:RegisterKeyframeSequence(rigged)
	task.spawn(function()
		local orai = true
		while state.demoToken == token and jin.Parent do
			if orai then
				text.Text = "往路: R15 の Ninja の走り（右）を、刃の骨（左）で流す"
				play(r15, "rbxassetid://10921157929")
				play(jin, "rbxassetid://10921157929")
			else
				text.Text = "復路: 刃の攻撃（左）を、R15（右）で流す"
				play(jin, attackPlain)
				play(r15, attackRigged)
			end
			orai = not orai
			task.wait(6)
		end
	end)
	return "左に刃の骨（青い棒、白い棒が顔の正面）、右に R15 を出し、往路と復路を 6 秒ずつ交互に流す（止めるのは MeshyRig.clear()）"
end

-- ===== 下忍の6項目の比較（#88。原本と、腰の移動を抜いた版を、ゲームの体の扱いと時間どおりに流す）=====
-- PM判断（2026-10-17）: 吹き飛び・打ち上げは腰の移動を全軸、ダウン・起き上がり・攻撃・のけぞりは水平だけ抜く。原本を残して比べる。
-- 確かめること: 二重移動（腰が根元の部品から離れる）、床への沈み・浮き、二重回転（倒れた体がさらに回る）。
-- 区間は musou の Motions.luau（MeshySources.Genin）、反応の秒数・軌道は Config.luau の EnemyReaction 節と Trajectory.luau を、
-- meshy-rig.project.json で ReplicatedStorage.Shared に入れた src/shared から引く（ゲームと同じ定義）

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config")) :: any
local GameMotions = require(Shared:WaitForChild("Motions")) :: any
local GameTrajectory = require(Shared:WaitForChild("Trajectory")) :: any

-- 下忍の6項目。clip は Jin.luau のクリップ、remove は腰の移動を抜く軸、flow はゲームでの体の扱い（Hanno）。
-- Air は手裏剣セットのチャージ攻撃（charge 段目）の吹き飛ばす強さで飛ばし、着地したら倒れて起き上がる
MeshyRig.GENIN = {
	Attack = { clip = "id219", remove = "xz", flow = "Stand" },
	Flinch = { clip = "id179", remove = "xz", flow = "Flinch" },
	Knockback = { clip = "id182", remove = "all", flow = "Air", reaction = "Knockback", charge = 1 },
	Launch = { clip = "id007", remove = "all", flow = "Air", reaction = "Launch", charge = 2 },
	Down = { clip = "id189", remove = "xz", flow = "Down" },
	GetUp = { clip = "id003", remove = "xz", flow = "Down" },
} :: { [string]: any }

-- 比べる場所の原点。床の上の面の高さがこの Y（Floor の上の面）。ほかのプレースで試すときは、床を置いてから差し替える
MeshyRig.ORIGIN = Vector3.zero
-- 倒れた体の根元の部品の高さ（EnemyService の LIE_HEIGHT と下忍の Scale 1）
local LIE_HEIGHT = 1
-- Hanno が着地を確かめる光線を、立っているときの高さより長くする分
local BELOW_MARGIN = 0.1
-- 二重移動とみなす腰の水平のずれ、沈む・浮くとみなす床からの高さ、二重回転とみなす胴の傾き
local DRIFT_LIMIT = 1
local SINK_LIMIT = -0.3
local FLOAT_LIMIT = 0.5
local TURN_LIMIT = 135
-- 待機（Ninja の待機。起き上がりの後に戻る）
local IDLE_ID = "rbxassetid://10921155160"

-- 腰の抜き方の説明（比べた結果の文に書く）
local REMOVE_NAMES = {
	xz = "腰の水平の移動を抜く",
	all = "腰の移動を全軸で抜く",
	pose = "腰の移動と回転を抜く（体の向きは Hanno の根元の部品に任せる）",
} :: { [string]: string }

-- KeyframeSequence の腰（Hips）の移動を抜いた写しを返す。mode は "xz"（水平だけ）、"all"（移動をすべて）、
-- "pose"（移動と回転をすべて。手足の姿だけを残す）。
-- 移動は腰の骨の休息の向きの中の値なので、model の腰の骨の向きで親の部品の向きへ直してから抜き、戻す
function MeshyRig.stripRoot(sequence: KeyframeSequence, mode: string, model: Model?): KeyframeSequence
	assert(REMOVE_NAMES[mode], `抜き方は xz・all・pose のどれか（{tostring(mode)}）`)
	local hips = model and findBone(model, "Hips")
	local rest = if hips then hips.CFrame.Rotation else CFrame.identity
	local copy = sequence:Clone()
	copy.Name = `{sequence.Name}_{mode}`
	for _, pose in copy:GetDescendants() do
		if pose:IsA("Pose") and pose.Name == "Hips" then
			if mode == "pose" then
				pose.CFrame = CFrame.identity
			else
				local moved = rest:VectorToWorldSpace(pose.CFrame.Position)
				moved = if mode == "xz" then Vector3.new(0, moved.Y, 0) else Vector3.zero
				pose.CFrame = CFrame.new(rest:VectorToObjectSpace(moved)) * pose.CFrame.Rotation
			end
		end
	end
	return copy
end

-- 取り込んだモデルのクリップ編集のクリップから、項目のクリップ（Jin.luau の名前を含むもの）を探す
local function savedClipFor(model: Model, clipKey: string): KeyframeSequence?
	local saves = game:GetService("ServerStorage"):FindFirstChild("RBX_ANIMSAVES")
	local holder = saves and saves:FindFirstChild(model.Name)
	local clip = Jin.clips[clipKey]
	if not holder or not clip then
		return nil
	end
	for _, child in holder:GetDescendants() do
		if child:IsA("KeyframeSequence") and string.find(child.Name, clip.name, 1, true) then
			return child
		end
	end
	return nil
end

-- 段の流れ。item は流すクリップの項目（nil は待機）、seconds はゲームでその状態が続く秒数、
-- root は根元の部品の扱い（Stand は立つ、Air は軌道、Lie は仰向けに寝かせる）
type Phase = { name: string, item: string?, seconds: number, root: string }

local function flowOf(item: string, entry: any, flight: number): { Phase }
	local reaction = GameConfig.EnemyReaction
	local after = {
		{ name = "倒れる", item = "Down", seconds = reaction.Down, root = "Lie" },
		{ name = "起き上がる", item = "GetUp", seconds = reaction.GetUp, root = "Stand" },
		{ name = "待機", item = nil, seconds = 0.6, root = "Stand" },
	}
	if entry.flow == "Air" then
		table.insert(after, 1, { name = "飛ぶ", item = item, seconds = flight, root = "Air" })
		return after
	elseif entry.flow == "Down" then
		return after
	elseif entry.flow == "Flinch" then
		return {
			{ name = "のけぞる", item = item, seconds = reaction.Flinch, root = "Stand" },
			{ name = "待機", item = nil, seconds = 0.6, root = "Stand" },
		}
	end
	local source = GameMotions.MeshySources.Genin[item]
	return {
		{ name = "攻撃", item = item, seconds = source.to - source.from, root = "Stand" },
		{ name = "待機", item = nil, seconds = 0.6, root = "Stand" },
	}
end

-- 比べる体1つ（原本か除去版）
type Body = {
	label: string,
	model: Model,
	root: BasePart,
	standHeight: number,
	-- 何も流していないときの、根元の部品から見た腰（LowerTorso）の位置
	restOffset: Vector3,
	base: Vector3,
	tracks: { [string]: AnimationTrack },
	idle: AnimationTrack,
}

-- 根元の部品の置き場所（Hanno と同じ。攻撃元は体の正面の +Z にいて、体は攻撃元の方を向く）
local function rootAt(body: Body, phase: Phase, tau: number, trajectory: any, landing: Vector3): CFrame
	local facing = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1))
	if phase.root == "Air" then
		local p = GameTrajectory.positionAt(trajectory, tau)
		return CFrame.new(body.base.X + p.x, MeshyRig.ORIGIN.Y + p.y, body.base.Z + p.z) * facing
	end
	local spot = if phase.name == "攻撃" or phase.name == "のけぞる" then body.base else body.base + landing
	if phase.root == "Lie" then
		return CFrame.new(spot.X, MeshyRig.ORIGIN.Y + LIE_HEIGHT, spot.Z) * facing * CFrame.Angles(math.rad(90), 0, 0)
	end
	return CFrame.new(spot.X, MeshyRig.ORIGIN.Y + body.standHeight, spot.Z) * facing
end

-- 終わりの姿で残すときに止める位置を、トラックの終わりからこの秒だけ手前にする（MotionPlayer の HOLD_MARGIN と同じ）
local HOLD_MARGIN = 1 / 30

-- 段の中の時刻 tau に流しているクリップの位置（区間の頭から等速、区間の終わりで止めて残す）。
-- track を渡すと、止める位置をトラックの終わりの手前に収める
local function clipPosition(item: string, tau: number, track: AnimationTrack?): number
	local source = GameMotions.MeshySources.Genin[item]
	local stop = source.to
	if track and track.Length > 0 then
		stop = math.min(stop, track.Length - HOLD_MARGIN)
	end
	return math.min(source.from + tau, stop)
end

-- 体の様子。腰の根元の部品からの水平のずれと縦のずれ、体の最も低い点の床からの高さ、胴（腰から頭）の鉛直からの傾き（度）
local function bodyStats(body: Body): (number, number, number, number)
	local model = body.model
	local lower = model:FindFirstChild("LowerTorso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local d = lower.Position - body.root.CFrame:PointToWorldSpace(body.restOffset)
	local lowest = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= body.root then
			local half = part.Size / 2
			for _, corner in
				{
					Vector3.new(-1, -1, -1),
					Vector3.new(-1, -1, 1),
					Vector3.new(-1, 1, -1),
					Vector3.new(-1, 1, 1),
					Vector3.new(1, -1, -1),
					Vector3.new(1, -1, 1),
					Vector3.new(1, 1, -1),
					Vector3.new(1, 1, 1),
				}
			do
				lowest = math.min(lowest, part.CFrame:PointToWorldSpace(corner * half).Y)
			end
		end
	end
	local up = (head.Position - lower.Position).Unit
	local tilt = math.deg(math.acos(math.clamp(up:Dot(Vector3.yAxis), -1, 1)))
	return Vector3.new(d.X, 0, d.Z).Magnitude, d.Y, lowest - MeshyRig.ORIGIN.Y, tilt
end

-- 体に、段の時刻 tau の姿勢を取らせる（測るとき。トラックは止めた位置で残す）
local function poseAt(body: Body, phase: Phase, tau: number, trajectory: any, landing: Vector3)
	body.root.CFrame = rootAt(body, phase, tau, trajectory, landing)
	for item, track in body.tracks do
		if item ~= phase.item then
			track:Stop(0)
		end
	end
	local track = if phase.item then body.tracks[phase.item] else body.idle
	if phase.item == nil then
		for _, other in body.tracks do
			other:Stop(0)
		end
	else
		body.idle:Stop(0)
	end
	if not track.IsPlaying then
		track:Play(0, 1, 0)
	end
	track.TimePosition = if phase.item then clipPosition(phase.item, tau, track) else tau
	track:AdjustSpeed(0)
end

type HikakuStat = {
	hMax: number,
	vMin: number,
	vMax: number,
	lowMin: number,
	lowMax: number,
	tiltMin: number,
	tiltMax: number,
}

local function newStat(): HikakuStat
	return {
		hMax = 0,
		vMin = math.huge,
		vMax = -math.huge,
		lowMin = math.huge,
		lowMax = -math.huge,
		tiltMin = math.huge,
		tiltMax = -math.huge,
	}
end

local function describeStat(stat: HikakuStat, phase: Phase): string
	local flags = {}
	if stat.hMax > DRIFT_LIMIT then
		table.insert(flags, "二重移動")
	end
	if stat.lowMin < SINK_LIMIT then
		table.insert(flags, "沈む")
	end
	if phase.root ~= "Air" and stat.lowMin > FLOAT_LIMIT then
		table.insert(flags, "浮く")
	end
	if stat.tiltMax > TURN_LIMIT then
		table.insert(flags, "二重回転")
	end
	return string.format(
		"腰のずれ 水平 最大 %.2f・縦 %.2f〜%.2f、床から %.2f〜%.2f、胴の傾き %.0f〜%.0f 度%s",
		stat.hMax,
		stat.vMin,
		stat.vMax,
		stat.lowMin,
		stat.lowMax,
		stat.tiltMin,
		stat.tiltMax,
		if #flags > 0 then `（{table.concat(flags, "・")}）` else ""
	)
end

-- R15 の体を1つ組み、項目のクリップのトラックを読み込む
local function buildBody(label: string, x: number, sequences: { [string]: KeyframeSequence }, subject: Model): Body
	local origin = MeshyRig.ORIGIN
	local model = MeshyRig.buildR15(CFrame.new(origin + Vector3.new(x, 3, -12)))
	model.Name = `R15_{label}`
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local lower = model:FindFirstChild("LowerTorso") :: BasePart
	local standHeight = humanoid.HipHeight + root.Size.Y / 2
	root.CFrame = CFrame.new(origin + Vector3.new(x, standHeight, -12))
		* CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1))
	task.wait(0.3)
	local restOffset = root.CFrame:PointToObjectSpace(lower.Position)
	local animator = animatorOf(model)
	local tracks: { [string]: AnimationTrack } = {}
	for item, sequence in sequences do
		local rigged = withoutRigData(sequence)
		rigDataFor(subject).Parent = rigged
		local animation = Instance.new("Animation")
		animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(rigged)
		local track = animator:LoadAnimation(animation)
		-- 終わりに着いても止まって姿が戻らないよう、くり返しにして止める位置で速さを 0 にする（MotionPlayer と同じ）
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		tracks[item] = track
	end
	local idleAnimation = Instance.new("Animation")
	idleAnimation.AnimationId = IDLE_ID
	local idle = animator:LoadAnimation(idleAnimation)
	idle.Looped = true
	idle.Priority = Enum.AnimationPriority.Idle
	-- 名札
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 0.3
	text.TextScaled = true
	text.Text = label
	text.Parent = gui
	gui.Parent = model:FindFirstChild("Head")
	return {
		label = label,
		model = model,
		root = root,
		standHeight = standHeight,
		restOffset = restOffset,
		base = origin + Vector3.new(x, 0, -12),
		tracks = tracks,
		idle = idle,
	}
end

-- 下忍の項目 item を、原本（左）と腰の移動を抜いた版（右）の R15 で、ゲームの体の扱いと時間どおりに比べる。
-- target を省くと合成した刃の骨（Jin.luau の GLB の値）、渡すと取り込んだモデル（クリップ編集で読み込んだクリップを
-- 名前で探し、無ければ Jin.luau の値）。modes で項目ごとの抜き方を差し替えられる（例: { Down = "pose" }）。
-- 測った後は、2体が同じ流れを繰り返す（止めるのは MeshyRig.clear()）
function MeshyRig.hikaku(item: string, target: Model?, modes: { [string]: string }?): string
	local entry = MeshyRig.GENIN[item]
	assert(entry, `項目は Attack・Flinch・Knockback・Launch・Down・GetUp のどれか（{tostring(item)}）`)
	MeshyRig.clear()
	state.demoToken += 1
	local token = state.demoToken
	local subject = target
		or MeshyRig.buildJin(CFrame.new(MeshyRig.ORIGIN + Vector3.new(0, 0.1, -30)) * CFrame.Angles(0, math.pi, 0))
	if not subject:FindFirstChildOfClass("HumanoidRigDescription") then
		MeshyRig.map(subject)
	end
	-- 流れ。飛ぶ時間は、立っているときの高さから軌道で飛び、足が床に届くまで（Hanno と同じ）
	local trajectory = nil
	local flight = 0
	local landing = Vector3.zero
	if entry.flow == "Air" then
		local hit = GameConfig.Bukishu.Shuriken.ChargeKogeki[entry.charge].Hits[1]
		local velocity =
			GameTrajectory.initialVelocity(entry.reaction, vector.create(0, 0, -1), hit.Knockback, false, 1)
		local probe = MeshyRig.buildR15(CFrame.new(MeshyRig.ORIGIN + Vector3.new(0, 3, -40)))
		local probeRoot = probe:FindFirstChild("HumanoidRootPart") :: BasePart
		local standHeight = (probe:FindFirstChildOfClass("Humanoid") :: Humanoid).HipHeight + probeRoot.Size.Y / 2
		probe:Destroy()
		trajectory = GameTrajectory.new(vector.create(0, standHeight, 0), velocity)
		flight = GameTrajectory.landingTime(trajectory, standHeight + BELOW_MARGIN) or 0
		local landed = GameTrajectory.positionAt(trajectory, flight)
		landing = Vector3.new(landed.x, 0, landed.z)
	end
	local phases = flowOf(item, entry, flight)
	-- クリップ（原本と除去版）。段で使う項目ごと
	local originals: { [string]: KeyframeSequence } = {}
	local removed: { [string]: KeyframeSequence } = {}
	local sourceNote = {}
	for _, phase in phases do
		local phaseItem = phase.item
		if phaseItem and not originals[phaseItem] then
			local phaseEntry = MeshyRig.GENIN[phaseItem]
			local saved = if target then savedClipFor(target, phaseEntry.clip) else nil
			local original = saved or clipToKeyframeSequence(phaseEntry.clip)
			local mode = if modes and modes[phaseItem] then modes[phaseItem] else phaseEntry.remove
			originals[phaseItem] = original
			removed[phaseItem] = MeshyRig.stripRoot(original, mode, subject)
			local source = GameMotions.MeshySources.Genin[phaseItem]
			table.insert(
				sourceNote,
				string.format(
					"%s は %s（%s、%.2f〜%.2f 秒、除去版は%s）",
					phaseItem,
					original.Name,
					if saved then "クリップ編集で読み込んだもの" else "Jin.luau の GLB の値",
					source.from,
					source.to,
					REMOVE_NAMES[mode]
				)
			)
		end
	end
	local bodies = {
		buildBody("原本", -4, originals, subject),
		buildBody("除去版", 4, removed, subject),
	}
	local flowText = {}
	for _, phase in phases do
		local clipText = if phase.item
			then string.format(
				"、%s の %.2f〜%.2f 秒",
				MeshyRig.GENIN[phase.item].clip,
				GameMotions.MeshySources.Genin[phase.item].from,
				clipPosition(phase.item, phase.seconds)
			)
			else ""
		table.insert(flowText, string.format("%s %.2f 秒%s", phase.name, phase.seconds, clipText))
	end
	local lines = {
		`比較 {item}（左が原本、右が除去版。ゲームの体の扱いと時間どおり。{subject.Name} の AnimationRigData で R15 へ移す）`,
		`- クリップ: {table.concat(sourceNote, "。")}`,
		`- 流れ: {table.concat(flowText, " → ")}`,
	}
	-- 段ごとに、段の中の 3 つの時刻で測る（待機は 1 つ）
	for _, phase in phases do
		local stats = { newStat(), newStat() }
		local fractions = if phase.item == nil then { 0.5 } else { 0.15, 0.5, 0.95 }
		for _, fraction in fractions do
			local tau = phase.seconds * fraction
			for _, body in bodies do
				poseAt(body, phase, tau, trajectory, landing)
			end
			task.wait(SETTLE)
			for index, body in bodies do
				local h, v, low, tilt = bodyStats(body)
				local stat = stats[index]
				stat.hMax = math.max(stat.hMax, h)
				stat.vMin = math.min(stat.vMin, v)
				stat.vMax = math.max(stat.vMax, v)
				stat.lowMin = math.min(stat.lowMin, low)
				stat.lowMax = math.max(stat.lowMax, low)
				stat.tiltMin = math.min(stat.tiltMin, tilt)
				stat.tiltMax = math.max(stat.tiltMax, tilt)
			end
		end
		table.insert(
			lines,
			`- {phase.name}: 原本 {describeStat(stats[1], phase)} / 除去版 {describeStat(stats[2], phase)}`
		)
	end
	-- 見るための再生。同じ流れを、1 秒の間を空けて繰り返す
	local total = 0
	for _, phase in phases do
		total += phase.seconds
	end
	local cycle = total + 1
	local started = os.clock()
	local current: { [Body]: number } = {}
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		if state.demoToken ~= token then
			if connection then
				connection:Disconnect()
			end
			return
		end
		local t = (os.clock() - started) % cycle
		local index, tau = #phases, phases[#phases].seconds
		local sum = 0
		for i, phase in phases do
			if t < sum + phase.seconds then
				index, tau = i, t - sum
				break
			end
			sum += phase.seconds
		end
		local phase = phases[index]
		for _, body in bodies do
			if not body.model.Parent then
				continue
			end
			body.root.CFrame = rootAt(body, phase, tau, trajectory, landing)
			if current[body] ~= index then
				current[body] = index
				for _, track in body.tracks do
					track:Stop(0.05)
				end
				if phase.item then
					body.idle:Stop(0.05)
					local track = body.tracks[phase.item]
					track:Play(0.05, 1, 1)
					track.TimePosition = clipPosition(phase.item, 0, track)
				elseif not body.idle.IsPlaying then
					body.idle:Play(0.1)
				end
			end
			if phase.item then
				local track = body.tracks[phase.item]
				local stop = clipPosition(phase.item, math.huge, track)
				if track.Speed > 0 and (track.TimePosition >= stop - 1 / 60 or tau >= phase.seconds - 1 / 60) then
					track:AdjustSpeed(0)
					track.TimePosition = math.min(track.TimePosition, stop)
				end
			end
		end
	end)
	table.insert(
		lines,
		"左右の2体が同じ流れを繰り返す（止めるのは MeshyRig.clear()）。腰のずれは根元の部品（当たり判定の位置）からの離れ、床からは体の最も低い点"
	)
	return table.concat(lines, "\n")
end

function MeshyRig.clear(): string
	state.demoToken += 1
	if state.sticks then
		state.sticks:Disconnect()
		state.sticks = nil
	end
	local found = workspace:FindFirstChild(FOLDER_NAME)
	if found then
		found:Destroy()
	end
	return "MeshyRigCheck を片づけた"
end

return MeshyRig
