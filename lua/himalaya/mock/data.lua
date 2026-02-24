local M = {}

--- Format offset seconds as an ISO date string relative to now (UTC).
--- @param offset number seconds from now (negative = past)
--- @return string
local function date(offset)
  return os.date('!%Y-%m-%d %H:%M:%S+00:00', os.time() + offset)
end

local people = {
  bob = { name = 'Bob Smith', addr = 'bob@example.com' },
  alice = { name = 'Alice Chen', addr = 'alice@example.com' },
  carol = { name = 'Carol Davis', addr = 'carol@example.com' },
  david = { name = 'David Lee', addr = 'david@example.com' },
  eve = { name = 'Eve Martin', addr = 'eve@example.com' },
  frank = { name = 'Frank Wilson', addr = 'frank@example.com' },
  grace = { name = 'Grace Kim', addr = 'grace@example.com' },
  helen = { name = 'Helen Park', addr = 'helen@example.com' },
}

local function env(id, subject, from, offset, flags, attachment)
  return {
    id = id,
    subject = subject,
    from = from,
    date = date(offset),
    flags = flags or {},
    has_attachment = attachment or false,
  }
end

--- All mock envelopes, newest first.
--- @return table[]
local function all_envelopes()
  return {
    -- Thread 1: Project Alpha release timeline (5 msgs)
    env(1005, 'Re: Project Alpha release timeline', people.bob, -3600, {}),
    env(1026, 'Have you tried the himalaya nvim plugin?', people.alice, -5000, {}),
    env(1004, 'Re: Project Alpha release timeline', people.david, -7200, { 'Seen' }),
    env(1003, 'Re: Project Alpha release timeline', people.carol, -10800, { 'Seen' }),
    env(1002, 'Re: Project Alpha release timeline', people.alice, -18000, { 'Seen' }),
    env(1001, 'Project Alpha release timeline', people.bob, -28800, { 'Seen' }),

    -- Thread 2: Code review (3 msgs)
    env(1008, 'Re: Code review: auth module refactor', people.eve, -43200, { 'Seen', 'Answered' }),
    env(1007, 'Re: Code review: auth module refactor', people.frank, -64800, { 'Seen' }),
    env(1006, 'Code review: auth module refactor', people.eve, -86400, { 'Seen' }),

    -- Thread 3: Team lunch (2 msgs)
    env(1010, 'Re: Team lunch this Friday?', people.bob, -129600, { 'Seen' }),
    env(1009, 'Team lunch this Friday?', people.grace, -172800, { 'Seen' }),

    -- Thread 4: Q1 budget (3 msgs)
    env(1013, 'Re: Q1 budget review', people.carol, -259200, { 'Seen' }),
    env(1012, 'Re: Q1 budget review', people.david, -345600, { 'Seen' }),
    env(1011, 'Q1 budget review', people.carol, -432000, { 'Seen', 'Flagged' }, true),

    -- Standalone messages
    env(
      1014,
      'Weekly newsletter: Tech digest',
      { name = 'TechDigest', addr = 'news@techdigest.io' },
      -21600,
      { 'Seen' }
    ),
    env(1015, 'Your PR #42 has been merged', { name = 'GitHub', addr = 'noreply@github.com' }, -36000, { 'Seen' }),
    env(
      1016,
      'Meeting reminder: Sprint planning',
      { name = 'Calendar', addr = 'calendar@company.com' },
      -50400,
      { 'Seen' },
      true
    ),
    env(
      1017,
      'Security alert: new login detected',
      { name = 'Security', addr = 'security@company.com' },
      -72000,
      { 'Flagged' }
    ),
    env(
      1018,
      'Invoice #2024-089 attached',
      { name = 'Billing', addr = 'billing@vendor.com' },
      -108000,
      { 'Seen' },
      true
    ),
    env(1019, 'Design review notes', people.helen, -144000, { 'Seen', 'Answered' }),
    env(1020, 'Quarterly OKR updates', { name = 'Manager', addr = 'manager@company.com' }, -187200, { 'Seen' }),
    env(1021, 'Open source contribution guide', { name = 'OpenSource', addr = 'oss@foundation.org' }, -216000, {}),
    env(
      1022,
      'Conference talk accepted!',
      { name = 'Events', addr = 'events@techconf.io' },
      -288000,
      { 'Flagged', 'Seen' }
    ),
    env(
      1023,
      'Package delivery notification',
      { name = 'Shipping', addr = 'track@logistics.com' },
      -360000,
      { 'Seen' }
    ),
    env(
      1024,
      'New comment on your blog post',
      { name = 'Blog', addr = 'noreply@blogplatform.com' },
      -396000,
      { 'Seen' }
    ),
    env(1025, 'Vacation request approved', { name = 'HR', addr = 'hr@company.com' }, -468000, { 'Seen' }),
  }
end

--- Build a lookup table of id → envelope from all_envelopes().
--- @return table<number, table>
local function envelope_map()
  local map = {}
  for _, e in ipairs(all_envelopes()) do
    map[e.id] = e
  end
  return map
end

--- @return table[]
function M.accounts()
  return {
    { name = 'personal', default = true },
    { name = 'work', default = false },
  }
end

--- @return table[]
function M.folders()
  return {
    { name = 'INBOX' },
    { name = 'Drafts' },
    { name = 'Sent' },
    { name = 'Archive' },
    { name = 'Trash' },
    { name = 'Spam' },
  }
end

--- Return envelopes for a folder, paginated.
--- @param folder string
--- @param page_size number
--- @param page number
--- @return table[]
function M.envelopes(folder, page_size, page, filter)
  local envs
  if folder == 'INBOX' or folder == '' then
    envs = all_envelopes()
  elseif folder == 'Sent' then
    envs = {
      env(2001, 'Re: Project Alpha release timeline', people.bob, -3600, { 'Seen' }),
      env(2002, 'Re: Code review: auth module refactor', people.eve, -14400, { 'Seen' }),
      env(2003, 'Re: Team lunch this Friday?', people.grace, -43200, { 'Seen' }),
      env(2004, 'Status update', people.alice, -86400, { 'Seen' }),
      env(2005, 'Meeting notes from standup', people.carol, -172800, { 'Seen' }),
      env(2006, 'Re: Q1 budget review', people.david, -259200, { 'Seen' }),
    }
  elseif folder == 'Drafts' then
    envs = {
      env(3001, 'Draft: Meeting agenda', people.bob, -7200, { 'Draft' }),
    }
  else
    envs = {}
  end

  if filter then
    local filtered = {}
    for _, e in ipairs(envs) do
      if filter(e) then
        filtered[#filtered + 1] = e
      end
    end
    envs = filtered
  end

  local start = (page - 1) * page_size + 1
  local result = {}
  for i = start, math.min(#envs, start + page_size - 1) do
    result[#result + 1] = envs[i]
  end
  return result
end

--- Return thread edges for a folder.
--- Each edge is {parent_env, child_env, depth}.
--- @param folder string
--- @return table[]
function M.thread_edges(folder)
  if folder ~= 'INBOX' and folder ~= '' then
    return {}
  end

  local map = envelope_map()
  local ghost = { id = 0, subject = '', from = { name = '', addr = '' }, date = '', flags = {} }

  local edges = {}
  local function edge(parent_id, child_id, depth)
    local parent = parent_id == 0 and ghost or map[parent_id]
    edges[#edges + 1] = { parent, map[child_id], depth }
  end

  -- Thread 1: Project Alpha release timeline
  edge(0, 1001, 0)
  edge(1001, 1002, 1)
  edge(1001, 1003, 1)
  edge(1003, 1004, 2)
  edge(1004, 1005, 3)

  -- Thread 2: Code review
  edge(0, 1006, 0)
  edge(1006, 1007, 1)
  edge(1007, 1008, 2)

  -- Thread 3: Team lunch
  edge(0, 1009, 0)
  edge(1009, 1010, 1)

  -- Thread 4: Q1 budget
  edge(0, 1011, 0)
  edge(1011, 1012, 1)
  edge(1012, 1013, 2)

  -- Standalone messages (each is a single-node thread)
  for _, id in ipairs({ 1026, 1014, 1015, 1016, 1017, 1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025 }) do
    edge(0, id, 0)
  end

  return edges
end

--- Return a mock email body.
--- @param id string|number
--- @return string
function M.message_body(id)
  id = tonumber(id) or 0
  local bodies = {
    [1001] = [[
From: Bob Smith <bob@example.com>
To: team@example.com
Subject: Project Alpha release timeline
Date: ]] .. date(-28800) .. [[

Hi team,

I'd like to discuss the release timeline for Project Alpha.
We're currently tracking well against our milestones, but
there are a few items that need attention:

1. API documentation is about 80% complete
2. Integration tests need another pass
3. The deployment pipeline is ready for staging

Can we schedule a quick sync this week to align on the
remaining tasks?

Best,
Bob]],
    [1002] = [[
From: Alice Chen <alice@example.com>
To: team@example.com
Subject: Re: Project Alpha release timeline
Date: ]] .. date(-18000) .. [[

> Can we schedule a quick sync this week to align on the
> remaining tasks?

Sounds good, Bob. Thursday afternoon works best for me.
I can share the API docs progress by then.

Alice]],
    [1003] = [[
From: Carol Davis <carol@example.com>
To: team@example.com
Subject: Re: Project Alpha release timeline
Date: ]] .. date(-10800) .. [[

> Can we schedule a quick sync this week to align on the
> remaining tasks?

Thursday works for me too. I'll prepare the integration
test coverage report.

Carol]],
    [1004] = [[
From: David Lee <david@example.com>
To: team@example.com
Subject: Re: Project Alpha release timeline
Date: ]] .. date(-7200) .. [[

> Thursday works for me too.

Same here. I'll have the staging deployment checklist
ready. One question — are we targeting the v2.1 or v2.2
branch for the release?

David]],
    [1005] = [[
From: Bob Smith <bob@example.com>
To: team@example.com
Subject: Re: Project Alpha release timeline
Date: ]] .. date(-3600) .. [[

> are we targeting the v2.1 or v2.2 branch for the release?

Good question. Let's go with v2.2 since it includes the
new auth module that Eve's been working on. Thursday at
3pm it is!

Bob]],
    [1026] = [[
From: Alice Chen <alice@example.com>
To: user@example.com
Subject: Have you tried the himalaya nvim plugin?
Date: ]] .. date(-5000) .. [[

Hey, have you tried himalaya-vim? Wondering if it's worth setting up.

Alice]],
    [1006] = [[
From: Eve Martin <eve@example.com>
To: frank@example.com
Subject: Code review: auth module refactor
Date: ]] .. date(-86400) .. [[

Hi Frank,

I've pushed the auth module refactor to the feature branch.
The main changes are:

- Moved from session-based to JWT authentication
- Added refresh token rotation
- Updated all middleware to use the new auth context

Could you take a look when you get a chance? No rush, but
it would be great to merge before the release sync.

Thanks,
Eve]],
    [1007] = [[
From: Frank Wilson <frank@example.com>
To: eve@example.com
Subject: Re: Code review: auth module refactor
Date: ]] .. date(-64800) .. [[

> Could you take a look when you get a chance?

Took a quick pass. Overall looks clean! A few suggestions:

1. The token validation could use a constant-time comparison
2. Consider adding rate limiting on the refresh endpoint
3. Minor: there's a typo in the error message on line 142

I'll approve once those are addressed.

Frank]],
    [1008] = [[
From: Eve Martin <eve@example.com>
To: frank@example.com
Subject: Re: Code review: auth module refactor
Date: ]] .. date(-43200) .. [[

> Took a quick pass. Overall looks clean!

Thanks for the thorough review, Frank! I've addressed all
three points. The constant-time comparison was a good catch.
Updated PR is ready for another look.

Eve]],
    [1009] = [[
From: Grace Kim <grace@example.com>
To: team@example.com
Subject: Team lunch this Friday?
Date: ]] .. date(-172800) .. [[

Hey everyone!

Anyone up for team lunch this Friday? I was thinking we
could try that new ramen place on 5th Street.

Let me know if you're in!

Grace]],
    [1010] = [[
From: Bob Smith <bob@example.com>
To: team@example.com
Subject: Re: Team lunch this Friday?
Date: ]] .. date(-129600) .. [[

> Anyone up for team lunch this Friday?

Count me in! I've heard great things about their tonkotsu.

Bob]],
    [1017] = [[
From: Security <security@company.com>
To: user@company.com
Subject: Security alert: new login detected
Date: ]] .. date(-72000) .. [[

A new sign-in to your account was detected:

  Device:   Linux (Firefox 125)
  Location: San Francisco, CA
  Time:     ]] .. date(-72000) .. [[

If this was you, no action is needed.
If not, please change your password immediately.

— Security Team]],
  }

  if bodies[id] then
    return bodies[id]
  end

  -- Generic body for messages without a specific template
  local map = envelope_map()
  local e = map[id]
  if e then
    return string.format(
      'From: %s <%s>\nTo: user@example.com\nSubject: %s\nDate: %s\n\nThis is the content of "%s".\n',
      e.from.name,
      e.from.addr,
      e.subject,
      e.date,
      e.subject
    )
  end

  return 'From: unknown@example.com\nTo: user@example.com\nSubject: Unknown\n\nMessage not found.\n'
end

--- Return a compose template for a new email.
--- @return string
function M.write_template()
  return 'From: user@example.com\nTo: \nSubject: \n\n'
end

--- Return a reply template.
--- @param id string|number
--- @return string
function M.reply_template(id)
  id = tonumber(id) or 0
  local map = envelope_map()
  local e = map[id]
  if not e then
    return M.write_template()
  end
  return string.format(
    'From: user@example.com\nTo: %s <%s>\nSubject: Re: %s\n\n> On %s, %s wrote:\n> ...\n\n',
    e.from.name,
    e.from.addr,
    e.subject:gsub('^Re: ', ''),
    e.date,
    e.from.name
  )
end

--- Return a forward template.
--- @param id string|number
--- @return string
function M.forward_template(id)
  id = tonumber(id) or 0
  local map = envelope_map()
  local e = map[id]
  if not e then
    return M.write_template()
  end
  return string.format(
    'From: user@example.com\nTo: \nSubject: Fwd: %s\n\n---------- Forwarded message ----------\nFrom: %s <%s>\nDate: %s\nSubject: %s\n\n...\n',
    e.subject:gsub('^Fwd: ', ''),
    e.from.name,
    e.from.addr,
    e.date,
    e.subject
  )
end

return M
