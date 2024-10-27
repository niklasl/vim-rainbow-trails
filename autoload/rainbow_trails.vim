vim9script

scriptencoding utf-8
var save_cpoptions = &cpoptions
set cpoptions&vim

# FIXME: Profile to see if we can optimise. Otherwise, just try pulling
#        calculations/def calls out of inner loops.

var matches = []
var timers = []

const default_colours = ['RainbowRed', 'RainbowOrange', 'RainbowYellow', 'RainbowGreen', 'RainbowBlue', 'RainbowIndigo', 'RainbowViolet']
const default_colour_width = 3
const default_colour_width_thresholds = [8]
const default_constant_interval = 1
const default_variable_timer_threshold = 30
const default_max_variable_interval = 5
const default_fade_rate_thresholds = [8, 30, 80, 150]

def rainbow_trails#enable(enable: number)
  # FIXME: Check for timers feature.
  # FIXME: Check for 256 colours or termguicolors
  if enable
    augroup RainbowTrails
      autocmd!
      autocmd CursorMoved * s:cursor_moved()
      autocmd WinLeave * s:stop_trails()
      autocmd WinEnter * w:rainbow_position = getpos('.')
      autocmd ColorScheme * s:setup_colors()
    augroup END
    w:rainbow_position = getpos('.')
    s:setup_colors()
  else
    autocmd! RainbowTrails
  endif
enddef


def s:setup_colors()
    # FIXME: Should we only highlight colours defined in s:colours()?
    highlight default RainbowRed guibg=#ff0000 ctermbg=196
    highlight default RainbowOrange guibg=#ff7f00 ctermbg=208
    highlight default RainbowYellow guibg=#ffff00 ctermbg=226
    highlight default RainbowGreen guibg=#00ff00 ctermbg=46
    highlight default RainbowBlue guibg=#0000ff ctermbg=21
    highlight default RainbowIndigo guibg=#00005f ctermbg=17
    highlight default RainbowViolet guibg=#7f00ff ctermbg=129
enddef


def s:cursor_moved()
  var new_position = getpos('.')
  if exists('w:rainbow_position')
    s:rainbow_start(new_position, w:rainbow_position)
  endif
  w:rainbow_position = new_position
enddef


def s:rainbow_start(new_position: list<number>, old_position: list<number>)
  var positions = s:bresenham(
        old_position[2], old_position[1],
        new_position[2], new_position[1])

  if len(positions) == 0
    return
  endif

  # How long before each character in the rainbow fades away
  # With a colour width of 1, the first position should start with a value of
  # num_colours - 1, because it *starts* as the first colour and then cycles
  # through the other colours which have indexes 1-6, one per callback.
  # With larger colour widths, we need to multiply by the width, so each
  # colour is maintained for that number of callbacks.
  #
  # So e.g. with a colour width of 3 and 7 colours, we want timers to contain:
  # [18, 19, 20, 21, ...]
  timers = range(len(positions))
  map(timers, (k, v) => v + (len(s:colours()) - 1) * s:colour_width(len(positions)))

  matches = []

  # Highlight everything with the first colour
  var first_colour_positions = copy(positions)
  while !empty(first_colour_positions)
    # FIXME: This limitation is no longer mentioned in the current :help
    # matchaddpos takes batches of up to 8 positions
    add(matches, matchaddpos(s:colours()[-1], first_colour_positions[ : 7]))
    first_colour_positions = first_colour_positions[8 : ]
  endwhile

  var timer_interval = max([1, get(g:, 'rainbow_constant_interval', default_constant_interval)])

  if len(timers) < s:variable_timer_threshold()
    # Map lengths of 1..<s:variable_timer_threshold to
    # rainbow_max_variable_interval-0 extra ms

    timer_interval += s:variable_interval(len(timers))
  endif
  var lfade_rate = -s:fade_rate(len(positions))
  var repeats = timers[-1] / lfade_rate + 1
  repeats += timers[-1] % lfade_rate > 0 ? 1 : 0

  add(
    timers,
    timer_start(
      timer_interval,
      function('s:rainbow_fade', [matches, positions, timers]),
      {'repeat': repeats}
    )
  )
enddef


def s:variable_interval(length: number): number
  # Convert max_variable_interval option to Float so entire calculation
  # below is coerced to Float
  var max_variable_interval = 1.0 * get(g:, 'rainbow_max_variable_interval', default_max_variable_interval)
  return float2nr(
    round(
        (max_variable_interval * (s:variable_timer_threshold() - length))
        / s:variable_timer_threshold()
    )
  )
enddef


def s:bresenham(x0: number, y0: number, x1: number, y1: number): list<list<number>>
  var positions = []

  var dx = abs(x1 - x0)
  var sx = x0 < x1 ? 1 : -1
  var dy = -abs(y1 - y0)
  var sy = y0 < y1 ? 1 : -1
  var error = dx + dy

  var x = x0
  var y = y0
  while 1
    # Don't add off-screen lines or lines hidden within closed folds
    if y >= line('w0') && y <= line('w$') && (foldclosed(y) == -1 || foldclosed(y) == y)
      add(positions, [y, x])
    endif
    if x == x1 && y == y1
      break
    endif
    var e2 = 2 * error
    if e2 >= dy
      if x == x1
        break
      endif
      error = error + dy
      x += sx
    endif
    if e2 <= dx
      if y == y1
        break
      endif
      error = error + dx
      y += sy
    endif
  endwhile

  return positions
enddef


def s:rainbow_fade(fmatches: list<number>, positions: list<list<number>>, ftimers: list<number>, timer_id: number)
  s:clear_matches(fmatches)

  var lcolour_width = s:colour_width(len(positions))

  var first_colour_positions = []
  for i in range(len(positions))
    const timer = ftimers[i]
    if timer <= 0
      continue
    elseif timer <= (len(s:colours())) * lcolour_width
      # Highlight this colour now, using 1-based indexing
      const colour_index = (timer + lcolour_width - 1) / lcolour_width - 1
      add(fmatches, matchaddpos(s:colours()[colour_index], [positions[i]]))
    else
      # Add to first_colour_positions to highlight at end of this loop
      add(first_colour_positions, positions[i])
    endif

    ftimers[i] += s:fade_rate(len(positions))
  endfor

  while !empty(first_colour_positions)
    add(fmatches, matchaddpos(s:colours()[-1], first_colour_positions[ : 7]))
    first_colour_positions = first_colour_positions[8 : ]
  endwhile
enddef


def s:fade_rate(rainbow_length: number): number
  var lfade_rate = min([-1, get(g:, 'rainbow_constant_interval', default_constant_interval)])

  for threshold in get(g:, 'rainbow_fade_rate_thresholds', default_fade_rate_thresholds)
    if rainbow_length >= threshold
      lfade_rate -= 1
    endif
  endfor

  return lfade_rate
enddef

def s:stop_trails()
  s:stop_timers()
  s:clear_matches(matches)
enddef


def s:stop_timers()
  for id in timers
    timer_stop(id)
  endfor

  timers = []
enddef


def s:colour_width(rainbow_length: number): number
  var lcolour_width = max([1, get(g:, 'rainbow_colour_width', default_colour_width)])
  for threshold in s:colour_width_thresholds()
    if rainbow_length >= threshold
      lcolour_width += 1
    endif
  endfor
  return lcolour_width
enddef


def s:clear_matches(fmatches: list<number>)
  for id in fmatches
    # FIXME: If the user starts two rainbows and switches windows before they
    #        complete, the second match is never deleted. Why?
    silent! matchdelete(id)
  endfor
  if !empty(fmatches)
    remove(fmatches, 0, -1)
  endif
enddef

#
# User Configuration Wrappers
#

def s:variable_timer_threshold(): number
  return get(g:, 'rainbow_variable_timer_threshold', default_variable_timer_threshold)
enddef


def s:colour_width_thresholds(): list<number>
  # FIXME: Should this be fully dynamic, instead of configurable? Can we come
  #        up with a nice implementation of that that always works?
  return get(g:, 'rainbow_colour_width_thresholds', default_colour_width_thresholds)
enddef


def s:colours(): list<string>
  return reverse(copy(get(g:, 'rainbow_colours', default_colours)))
enddef


&cpoptions = save_cpoptions
