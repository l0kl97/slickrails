import { expect, test } from 'claude-code/testing'

import { line, parse } from './register'

const PORCELAIN = [
  'installed=1', 'hooks=1', 'guard=1', 'review=claude', 'gate=green', 'gate_age=60',
  'rules_done=6', 'rules_total=12', 'rules_open=6', 'dossiers=3',
].join('\n')

test('the status line sums up what slickrails status --porcelain says', () => {
  expect(line(parse(PORCELAIN))).toBe('slickrails ✓ guard · review claude · checks ✓ · 6 rules open')
})

test('what is off is said, not hidden', () => {
  const off = parse('installed=1\nhooks=0\nguard=0\nreview=off\ngate=red\nrules_open=0\n')
  expect(line(off)).toBe('slickrails ✗ guard off · ✗ git hooks off · review off · checks ✗ · all rules in place')
})

test('outside a slickrails repo the line stays empty', () => {
  expect(line(parse('installed=0\n'))).toBeUndefined()
  expect(line(parse(''))).toBeUndefined()
})

test('session start shows the line, and /slickrails answers with the full status', async ($, on) => {
  const shown: (string | undefined)[] = []
  on('command.register', () => ({ value: { command: 'slickrails' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => ({
    value: { exitCode: 0, stdout: e.argv.includes('--porcelain') ? PORCELAIN : 'slickrails status — app (main)', stderr: '' },
  }))
  on('ui.status', (_, e) => { shown.push(e.text); return { value: undefined } })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await new Promise(resolve => setTimeout(resolve, 0))
  expect(shown).toContain('slickrails ✓ guard · review claude · checks ✓ · 6 rules open')

  const ran = await $.command.run({ command: 'slickrails', args: '' })
  expect(ran.text).toContain('slickrails status — app (main)')
})
