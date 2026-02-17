function! himalaya#domain#email#flags#complete(arg_lead, cmd_line, cursor_pos) abort
  return luaeval("require('himalaya.domain.email.flags').complete(_A[1], _A[2], _A[3])", [a:arg_lead, a:cmd_line, a:cursor_pos])
endfunction
