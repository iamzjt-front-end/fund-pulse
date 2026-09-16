import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

for (const keychain of ['', '/tmp/a keychain.keychain-db']) {
  test(`local packaging reaches build with ${keychain ? 'explicit' : 'default'} notary keychain on system Bash`, () => {
    const directory = mkdtempSync(path.join(tmpdir(), 'fund-pulse-package-test-'));
    try {
      mkdirSync(path.join(directory, 'script')); mkdirSync(path.join(directory, 'bin'));
      copyFileSync(path.join(root, 'script/package_swift.sh'), path.join(directory, 'script/package_swift.sh'));
      writeFileSync(path.join(directory, 'package.json'), JSON.stringify({ version: '1.0' }));
      writeFileSync(path.join(directory, 'script/build_and_run.sh'), '#!/bin/sh\nexit 77\n', { mode: 0o755 });
      writeFileSync(path.join(directory, 'bin/xcrun'), '#!/bin/sh\nprintf "%s\\n" "$@" > "$NOTARY_LOG"\n', { mode: 0o755 });
      const log = path.join(directory, 'notary.log');
      const result = spawnSync('/bin/bash', [path.join(directory, 'script/package_swift.sh')], {
        cwd: directory, encoding: 'utf8', env: { ...process.env, PATH: `${directory}/bin:${process.env.PATH}`,
          FUND_PULSE_SIGN_IDENTITY: 'Developer ID Application: Test (TEAM123456)',
          FUND_PULSE_SKIP_NOTARY: '0', FUND_PULSE_NOTARY_KEYCHAIN: keychain, NOTARY_LOG: log }
      });
      assert.equal(result.status, 77, result.stderr);
      const argumentsUsed = readFileSync(log, 'utf8').trim().split('\n');
      assert.deepEqual(argumentsUsed.slice(-2), keychain ? ['--keychain', keychain] : ['--keychain-profile', 'fund-pulse']);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
}

for (const packageExit of [0, 42]) {
  test(`CI signing cleans ephemeral credentials after package exits ${packageExit}`, () => {
    const directory = mkdtempSync(path.join(tmpdir(), 'fund-pulse-signing-test-'));
    try {
      const bin = path.join(directory, 'bin'); mkdirSync(bin);
      const log = path.join(directory, 'commands');
      for (const command of ['security', 'xcrun', 'npm']) {
        writeFileSync(path.join(bin, command), `#!/bin/sh\nprintf '%s\\n' '${command}' "$1" "\${2:-}" >> "$COMMAND_LOG"\n` +
          (command === 'security' ? 'if [ "$1" = list-keychains ]; then echo "\\"/tmp/original.keychain-db\\""; fi\n' : '') +
          (command === 'npm' ? `exit ${packageExit}\n` : 'exit 0\n'), { mode: 0o755 });
      }
      const result = spawnSync('bash', [path.join(root, 'script/ci_package.sh')], {
        cwd: root, encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}`,
          RUNNER_TEMP: directory, COMMAND_LOG: log,
          MACOS_CERTIFICATE_BASE64: Buffer.from('fake-cert').toString('base64'), MACOS_CERTIFICATE_PASSWORD: 'private-password',
          FUND_PULSE_SIGN_IDENTITY: 'Developer ID Application: Test (TEAM123456)',
          APPLE_ID: 'test@example.invalid', APPLE_TEAM_ID: 'TEAM123456', APPLE_APP_PASSWORD: 'private-notary-password' }
      });
      assert.equal(result.status, packageExit, result.stderr);
      const calls = readFileSync(log, 'utf8');
      assert.ok(calls.indexOf('import') < calls.indexOf('npm\nrun'), 'certificate imported before packaging');
      assert.match(calls, /store-credentials/);
      assert.match(calls, /delete-keychain/);
      assert.doesNotMatch(result.stdout + result.stderr, /private-password|private-notary-password/);
      assert.equal(spawnSync('find', [directory, '-name', '*.p12'], { encoding: 'utf8' }).stdout.trim(), '');
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
}

test('CI fails closed before packaging without signing credentials', () => {
  const result = spawnSync('bash', [path.join(root, 'script/ci_package.sh')], {
    encoding: 'utf8', env: { PATH: process.env.PATH, HOME: process.env.HOME }
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /MACOS_CERTIFICATE_BASE64/);
});

test('workflows use signing lifecycle and have no unreachable release-only branch', () => {
  for (const name of ['publish', 'beta']) {
    const workflow = readFileSync(path.join(root, `.github/workflows/${name}.yml`), 'utf8');
    assert.match(workflow, /script\/ci_package.sh/);
    assert.match(workflow, /DEVELOPER_DIR/);
    assert.doesNotMatch(workflow, /github\.event_name == 'release'/);
    assert.match(workflow, /test:ci/);
  }
});
