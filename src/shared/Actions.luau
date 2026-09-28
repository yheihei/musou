--!strict
-- クライアント → サーバーの Remotes.Action で送る行動の種類

export type Action = "Attack" | "ChargeKogeki" | "Ougi"

local Actions = {
	Attack = "Attack" :: Action,
	ChargeKogeki = "ChargeKogeki" :: Action,
	Ougi = "Ougi" :: Action,
}

function Actions.isValid(value: unknown): boolean
	return value == Actions.Attack or value == Actions.ChargeKogeki or value == Actions.Ougi
end

return Actions
