-- Psql-style scratchpad for the claude-code.nvim terminal
local M = {}

-- Check if current buffer is a Claude Code terminal
local function is_current_claude_term()
  local buf = vim.api.nvim_get_current_buf()
  return vim.bo[buf].buftype == 'terminal'
         and vim.api.nvim_buf_get_name(buf):match('claude%-code') ~= nil
end

-- Open a vim buffer for editing Claude input. Only works from Claude terminal.
function M.open_editor()
  if not is_current_claude_term() then
    vim.notify('Claude Code terminal must be focused to open editor', vim.log.levels.INFO)
    return
  end

  -- Capture the terminal window we'll send text to later
  local term_win = vim.api.nvim_get_current_win()

  -- Create a new vertical split on the left (80 columns)
  vim.cmd('topleft vertical 80vnew')
  local edit_buf = vim.api.nvim_get_current_buf()

  -- Set up the scratch buffer
  vim.bo[edit_buf].buftype = 'acwrite'  -- Custom write handling
  vim.bo[edit_buf].swapfile = false
  vim.bo[edit_buf].bufhidden = 'wipe'   -- Clean up when window closes
  vim.bo[edit_buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(edit_buf, 'claude://scratchpad_message')

  -- Store terminal window ID - this is how we know where to send text
  vim.b._claude_target_win = term_win

  -- Start in insert mode for immediate typing
  vim.cmd('startinsert')
  
  -- Handle save events (both :w and :wq)
  vim.api.nvim_create_augroup('ClaudeCodeScratchpad', { clear = false })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = 'ClaudeCodeScratchpad',
    buffer = edit_buf,
    callback = function(args)
      -- Get the terminal window we stored earlier
      local tgt_win = vim.b._claude_target_win
      if not vim.api.nvim_win_is_valid(tgt_win) then
        vim.notify('Original Claude window vanished', vim.log.levels.ERROR)
        return
      end

      -- Get the terminal's channel ID for sending text
      local term_buf = vim.api.nvim_win_get_buf(tgt_win)
      local ok, chan = pcall(vim.api.nvim_buf_get_var, term_buf, 'terminal_job_id')
      if not ok or not tonumber(chan) or tonumber(chan) == 0 then
        vim.notify('Could not get channel ID for Claude terminal', vim.log.levels.ERROR)
        return
      end

      -- Collect all lines and join with newlines
      local text = table.concat(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false), '\n')
      
      -- Send text to the terminal
      local ok, err = pcall(vim.api.nvim_chan_send, chan, text)
      if not ok then
        vim.notify('Send failed: ' .. tostring(err), vim.log.levels.ERROR)
        return
      end

      -- Mark buffer as saved so :wq works correctly
      vim.bo[args.buf].modified = false
    end,
  })
end

return M