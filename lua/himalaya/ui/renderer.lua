local config = require("himalaya.config")

local M = {}

local ascii_symbols = {
	unseen = "*",
	answered = "R",
	flagged = "!",
	attachment = "@",
	header = "FLGS",
}

local nerd_symbols = {
	unseen = "",
	answered = "",
	flagged = "󰈿",
	attachment = "",
	header = "",
}

--- Map JSON flags array + has_attachment to compact symbols.
--- @param envelope table
--- @return string
function M.format_flags(envelope)
	local sym = config.get().use_nerd and nerd_symbols or ascii_symbols
	local s = ""
	local flags = envelope.flags or {}
	local seen = false
	local answered = false
	local flagged = false

	for _, f in ipairs(flags) do
		if f == "Seen" then
			seen = true
		end
		if f == "Answered" then
			answered = true
		end
		if f == "Flagged" then
			flagged = true
		end
	end

	local use_nerd = config.get().use_nerd
	local sp = " "

	-- Each slot: symbol + space (2 display cols)
	-- Order: flagged (rarest) → unseen → answered → attachment (most common)
	local s = (flagged and sym.flagged or sp) .. sp
	if config.get().show_unseen_flag then
		s = s .. (not seen and sym.unseen or sp) .. sp
	end
	s = s .. (answered and sym.answered or sp) .. sp
	s = s .. (envelope.has_attachment and sym.attachment or sp) .. sp
	return s
end

--- Prefer `.name`, fall back to `.addr`.
--- @param from table|nil
--- @return string
function M.format_from(from)
	if not from then
		return ""
	end
	if from.name and from.name ~= vim.NIL and from.name ~= "" then
		return from.name
	end
	if from.addr and from.addr ~= vim.NIL and from.addr ~= "" then
		return from.addr
	end
	return ""
end

--- Pad or truncate a string to exactly `width` display columns.
--- Uses vim.fn.strdisplaywidth and vim.fn.strcharpart for multi-byte safety.
--- Truncated strings get a trailing `~`.
--- @param s string
--- @param width number
--- @return string
function M.fit(s, width)
	if width <= 0 then
		return ""
	end
	s = tostring(s)
	local dw = vim.fn.strdisplaywidth(s)
	if dw == width then
		return s
	elseif dw < width then
		return s .. string.rep(" ", width - dw)
	else
		local nchars = vim.fn.strchars(s)
		for i = nchars - 1, 0, -1 do
			local sub = tostring(vim.fn.strcharpart(s, 0, i))
			local subdw = vim.fn.strdisplaywidth(sub)
			if subdw <= width - 1 then
				sub = sub .. "~"
				local finaldw = vim.fn.strdisplaywidth(sub)
				if finaldw < width then
					sub = sub .. string.rep(" ", width - finaldw)
				end
				return sub
			end
		end
		return "~" .. string.rep(" ", math.max(0, width - 1))
	end
end

-- Box-drawing characters (hex-escaped for tokenizer safety)
local BOX_V = "\xe2\x94\x82" -- │
local BOX_H = "\xe2\x94\x80" -- ─
local BOX_CROSS = "\xe2\x94\xbc" -- ┼

--- Render envelopes into box-drawn display lines.
--- Returns {header_line, separator_line, data_line_1, ...}
--- Fixed widths: ID=6, FLAGS=6|8, DATE=19
--- Remaining space split 60/40 between SUBJECT and FROM
--- @param envelopes table[]
--- @param total_width number
--- @return string[]
function M.render(envelopes, total_width)
	local use_nerd = config.get().use_nerd
	local id_w = 6
	local num_slots = config.get().show_unseen_flag and 4 or 3
	local flags_w = num_slots * 2
	local date_w = 19
	-- Format: " col │ col │ col │ col │ col"
	-- Overhead: 1 (leading space) + 4x " │ " separators (4*3=12) = 13
	local overhead = 13
	local fixed = id_w + flags_w + date_w
	local remaining = total_width - fixed - overhead
	if remaining < 2 then
		remaining = 2
	end

	local subject_w = math.floor(remaining * 0.6)
	local from_w = remaining - subject_w

	local sym = use_nerd and nerd_symbols or ascii_symbols
	local col_sep = " " .. BOX_V .. " "
	local row_fmt = " %s" .. col_sep .. "%s" .. col_sep .. "%s" .. col_sep .. "%s" .. col_sep .. "%s"

	local lines = {}

	local header = string.format(
		row_fmt,
		M.fit("ID", id_w),
		M.fit(sym.header, flags_w),
		M.fit("SUBJECT", subject_w),
		M.fit("FROM", from_w),
		M.fit("DATE", date_w)
	)
	table.insert(lines, header)

	-- Horizontal separator under header
	local cross_sep = BOX_H .. BOX_CROSS .. BOX_H
	local separator = string.rep(BOX_H, 1 + id_w)
		.. cross_sep
		.. string.rep(BOX_H, flags_w)
		.. cross_sep
		.. string.rep(BOX_H, subject_w)
		.. cross_sep
		.. string.rep(BOX_H, from_w)
		.. cross_sep
		.. string.rep(BOX_H, date_w)
	table.insert(lines, separator)

	for _, env in ipairs(envelopes) do
		local id = tostring(env.id or "")
		local flags = M.format_flags(env)
		local subject = env.subject or ""
		local from = ""
		if env.from and env.from ~= vim.NIL then
			if env.from.name or env.from.addr then
				from = M.format_from(env.from)
			elseif type(env.from) == "table" and #env.from > 0 then
				from = M.format_from(env.from[1])
			end
		end
		local date = env.date or ""

		local line = string.format(
			row_fmt,
			M.fit(id, id_w),
			M.fit(flags, flags_w),
			M.fit(subject, subject_w),
			M.fit(from, from_w),
			M.fit(date, date_w)
		)
		table.insert(lines, line)
	end

	return lines
end

return M
