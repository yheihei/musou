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
