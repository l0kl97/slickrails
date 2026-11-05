#!/usr/bin/env node
// npx slickrails — bootstraps the kit into ~/.slickrails and forwards the command.
// The kit itself is POSIX shell; this shim only ensures it is present and current.
'use strict';

const { execFileSync } = require('node:child_process');
const { existsSync } = require('node:fs');
const { join } = require('node:path');
const os = require('node:os');

const REPO = process.env.SLICKRAILS_REPO || 'https://github.com/l0kl97/slickrails.git';
const HOME = process.env.SLICKRAILS_HOME || join(os.homedir(), '.slickrails');

function sh(cmd, args, opts = {}) {
  execFileSync(cmd, args, { stdio: 'inherit', ...opts });
}

try {
  if (existsSync(join(HOME, '.git'))) {
    execFileSync('git', ['-C', HOME, 'pull', '--ff-only', '--quiet'], { stdio: 'ignore' });
  } else {
    console.log(`slickrails: fetching kit into ${HOME}`);
    sh('git', ['clone', '--depth', '1', REPO, HOME]);
  }
} catch (e) {
  console.error('slickrails: could not fetch/update the kit (is git installed and the network up?)');
  process.exit(1);
}

const args = process.argv.slice(2);
try {
  sh('sh', [join(HOME, 'bin', 'slickrails'), ...(args.length ? args : ['help'])]);
} catch (e) {
  process.exit(e.status || 1);
}
