import type { EngineInterface, Register } from 'claude-code'

// slickrails-status: one line in Claude Code's status line on where this repo stands with slickrails, and
// /slickrails for the whole picture. The facts come from `slickrails status --porcelain` (the kit decides,
// this only shows); outside a slickrails repo the line stays empty.

// the slickrails CLI on PATH, else where the one-line installer puts it
const CLI = 'command -v slickrails >/dev/null 2>&1 && exec slickrails "$@" || exec sh "$HOME/.slickrails/bin/slickrails" "$@"'
const MIN_GAP_MS = 15_000 // after every turn, but not more often than this

type Facts = Record<string, string>

export const parse = (text: string): Facts =>
  Object.fromEntries(
    text
      .split('\n')
      .map(line => line.split('='))
      .filter(kv => kv.length >= 2 && kv[0] !== '')
      .map(([k, ...v]) => [k, v.join('=')]),
  )

export const line = (f: Facts): string | undefined => {
  if (f.installed !== '1') return undefined
  const parts = [
    f.guard === '1' ? '✓ guard' : '✗ guard off',
    f.hooks === '1' ? undefined : '✗ git hooks off',
    f.review && f.review !== 'off' ? `review ${f.review}` : 'review off',
    f.gate === 'green' ? 'checks ✓' : f.gate === 'red' ? 'checks ✗' : undefined,
    Number(f.rules_open) > 0 ? `${f.rules_open} rules open` : 'all rules in place',
  ]
  return `slickrails ${parts.filter(Boolean).join(' · ')}`
}

let lastRun = 0

async function refresh($: EngineInterface): Promise<void> {
  lastRun = Date.now()
  try {
    const ran = await $.process.run(['sh', '-c', CLI, 'slickrails', 'status', '--porcelain'], { timeoutMs: 10_000 })
    $.ui.status(ran.exitCode === 0 ? line(parse(ran.stdout)) : undefined)
  } catch {
    $.ui.status(undefined) // no slickrails CLI here: show nothing rather than something wrong
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({ name: 'slickrails', description: 'Where this repo stands with slickrails' })
    void refresh($)
    return started
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (Date.now() - lastRun >= MIN_GAP_MS) void refresh($)
    return done
  })

  on('command.run', { command: 'slickrails' }, async $ => {
    try {
      const ran = await $.process.run(['sh', '-c', CLI, 'slickrails', 'status'], { timeoutMs: 60_000 })
      void refresh($)
      return { text: (ran.stdout || ran.stderr).trimEnd() || 'slickrails status printed nothing.' }
    } catch {
      return { text: 'slickrails is not installed here: curl -fsSL https://raw.githubusercontent.com/l0kl97/slickrails/main/bootstrap.sh | sh' }
    }
  })
}
