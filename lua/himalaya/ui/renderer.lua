local config = require("himalaya.config")
local perf = require("himalaya.perf")

local M = {}

local FLAG_ORDER = { "flagged", "unseen", "answered", "attachment" }
M.FLAG_ORDER = FLAG_ORDER

--- Map JSON flags array + has_attachment to compact symbols.
--- @param envelope table
--- @param cfg? table  optional config (defaults to config.get())
--- @return string
function M.format_flags(envelope, cfg)
	local cfg_flags = (cfg or config.get()).flags
	local raw = envelope.flags or {}
	local seen, answered, flagged = false, false, false

	for _, f in ipairs(raw) do
		if f == "Seen" then seen = true end
		if f == "Answered" then answered = true end
		if f == "Flagged" then flagged = true end
	end

	local active = {
		flagged = flagged,
		unseen = not seen,
		answered = answered,
		attachment = envelope.has_attachment and true or false,
	}

	local s = ""
	for _, key in ipairs(FLAG_ORDER) do
		local sym = cfg_flags[key]
		if type(sym) == "string" then
			s = s .. (active[key] and sym or " ") .. " "
		end
	end
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

--- Format a date string using the configured format.
--- Parses ISO-ish dates from himalaya (e.g. "2026-02-17 13:18+00:00")
--- and reformats using strftime-style tokens. Converts to local time.
--- Returns the raw string when no date_format is configured.
--- @param raw string
--- @param cfg? table  optional config (defaults to config.get())
--- @return string
function M.format_date(raw, cfg)
	perf.count("format_date")
	local fmt = (cfg or config.get()).date_format
	if not fmt or raw == "" then
		return raw
	end

	-- Parse: "YYYY-MM-DD HH:MM:SS±HH:MM" or "YYYY-MM-DDTHH:MM:SSZ"
	local y, mo, d, h, mi, s, tz = raw:match("^(%d+)-(%d+)-(%d+)[T%s](%d+):(%d+):?(%d*)(.*)")
	if not y then
		return raw
	end
	s = (s ~= "") and tonumber(s) or 0

	-- Parse timezone offset and convert to UTC epoch
	local tz_offset = 0
	if tz ~= "" and tz ~= "Z" then
		local tz_sign, tz_h, tz_m = tz:match("^([%+%-])(%d+):(%d+)")
		if tz_sign then
			tz_offset = (tonumber(tz_h) * 3600 + tonumber(tz_m) * 60)
			if tz_sign == "-" then tz_offset = -tz_offset end
		end
	end

	local utc_epoch = os.time({
		year = tonumber(y), month = tonumber(mo), day = tonumber(d),
		hour = tonumber(h), min = tonumber(mi), sec = s,
	}) - tz_offset

	-- Format in local time
	return os.date(fmt, utc_epoch)
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
	perf.count("fit")
	local dw = vim.fn.strdisplaywidth(s)
	perf.count("strdisplaywidth")
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
M.BOX_V = BOX_V
M.BOX_H = BOX_H
M.BOX_CROSS = BOX_CROSS

--- Compute column widths, row format, header, and separator for the 5-column layout.
--- @param items table[] input array (envelopes or display_rows)
--- @param total_width number available display width
--- @param get_env_fn function(item): envelope  extracts envelope from each item
--- @param cfg? table  optional config (defaults to config.get())
--- @return table { id_w, flags_w, date_w, subject_w, from_w, row_fmt, header, separator }
function M.compute_layout(items, total_width, get_env_fn, cfg)
	cfg = cfg or config.get()
	local cfg_flags = cfg.flags
	local id_w = 2 -- minimum: fits "ID" header
	for _, item in ipairs(items) do
		local env = get_env_fn(item)
		local len = #tostring(env.id or "")
		if len > id_w then id_w = len end
	end
	local num_slots = 0
	for _, key in ipairs(FLAG_ORDER) do
		if type(cfg_flags[key]) == "string" then num_slots = num_slots + 1 end
	end
	local flags_w = num_slots * 2
	local date_w = 4 -- minimum: fits "DATE" header
	-- format_date with a fixed strftime format produces constant-width output,
	-- so formatting one sample is sufficient instead of formatting all N dates.
	for _, item in ipairs(items) do
		local env = get_env_fn(item)
		local raw = tostring(env.date or "")
		if raw ~= "" then
			local len = #M.format_date(raw, cfg)
			if len > date_w then date_w = len end
			break
		end
	end
	local gutters = cfg.gutters
	-- With gutters:    " col │ col │ col │ col │ col" → 1 + 4×3 = 13
	-- Without gutters: "col│col│col│col│col"          → 4×1 = 4
	local overhead = gutters and 13 or 4
	local fixed = id_w + flags_w + date_w
	local remaining = total_width - fixed - overhead
	if remaining < 2 then
		remaining = 2
	end

	local subject_w = math.floor(remaining * 0.6)
	local from_w = remaining - subject_w

	local col_sep = gutters and (" " .. BOX_V .. " ") or BOX_V
	local leading = gutters and " " or ""
	local row_fmt = leading .. "%s" .. col_sep .. "%s" .. col_sep .. "%s" .. col_sep .. "%s" .. col_sep .. "%s"

	local header = string.format(
		row_fmt,
		M.fit("ID", id_w),
		M.fit(cfg_flags.header or "FLGS", flags_w),
		M.fit("SUBJECT", subject_w),
		M.fit("FROM", from_w),
		M.fit("DATE", date_w)
	)

	-- Horizontal separator under header
	local cross_sep = gutters and (BOX_H .. BOX_CROSS .. BOX_H) or BOX_CROSS
	local leading_h = gutters and string.rep(BOX_H, 1 + id_w) or string.rep(BOX_H, id_w)
	local separator = leading_h
		.. cross_sep
		.. string.rep(BOX_H, flags_w)
		.. cross_sep
		.. string.rep(BOX_H, subject_w)
		.. cross_sep
		.. string.rep(BOX_H, from_w)
		.. cross_sep
		.. string.rep(BOX_H, date_w)

	return {
		id_w = id_w, flags_w = flags_w, date_w = date_w,
		subject_w = subject_w, from_w = from_w,
		row_fmt = row_fmt, header = header, separator = separator,
	}
end

--- Identity envelope extractor for flat listing.
local function env_identity(item) return item end

--- Render envelopes into box-drawn display lines.
--- Returns { header = string, separator = string, lines = string[] }
--- Fixed widths: ID=6, FLAGS=6|8, DATE=19
--- Remaining space split 60/40 between SUBJECT and FROM
--- @param envelopes table[]
--- @param total_width number
--- @param cfg? table  optional config (defaults to config.get())
--- @return table
function M.render(envelopes, total_width, cfg)
	perf.start("renderer.render")
	cfg = cfg or config.get()
	local layout = M.compute_layout(envelopes, total_width, env_identity, cfg)

	local lines = {}
	for _, env in ipairs(envelopes) do
		local id = tostring(env.id or "")
		local flags = M.format_flags(env, cfg)
		local subject = env.subject or ""
		local from = ""
		if env.from and env.from ~= vim.NIL then
			if env.from.name or env.from.addr then
				from = M.format_from(env.from)
			elseif type(env.from) == "table" and #env.from > 0 then
				from = M.format_from(env.from[1])
			end
		end
		local date = M.format_date(env.date or "", cfg)

		local line = string.format(
			layout.row_fmt,
			M.fit(id, layout.id_w),
			M.fit(flags, layout.flags_w),
			M.fit(subject, layout.subject_w),
			M.fit(from, layout.from_w),
			M.fit(date, layout.date_w)
		)
		table.insert(lines, line)
	end

	perf.stop("renderer.render")
	return { header = layout.header, separator = layout.separator, lines = lines }
end

return M
