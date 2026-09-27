--!strict
-- クライアント → サーバーの Remotes.Action で送る行動の種類

export type Action = "Attack" | "Charge" | "Musou"

local Actions = {
	Attack = "Attack" :: Action,
	Charge = "Charge" :: Action,
	Musou = "Musou" :: Action,
}

function Actions.isValid(value: unknown): boolean
	return value == Actions.Attack or value == Actions.Charge or value == Actions.Musou
end

return Actions
