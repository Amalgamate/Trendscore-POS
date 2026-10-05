import { randomBytes } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promises as fs } from 'node:fs';
import type {
  CommandResult,
  HostFs,
  ProvisioningDeps,
  SecretGenerator,
} from './types.js';

/**
 * Real implementations of the provisioning ports.
 *
 * The CLI uses these. Tests use in-memory fakes, which is why the engine
 * itself needs no Docker to be exercised.
 */

/**
 * Restricted password alphabet. Ambiguous characters (0/O, 1/l/I) are
 * excluded because an operator will eventually read a password aloud to
 * support over the phone.
 */
const PASSWORD_ALPHABET = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function createSecretGenerator(): SecretGenerator {
  return {
    token(bytes = 24): string {
      return randomBytes(bytes).toString('base64url');
    },
    base64(bytes = 32): string {
      return randomBytes(bytes).toString('base64');
    },
    password(length = 32): string {
      const bytes = randomBytes(length);
      let out = '';
      for (let i = 0; i < length; i++) {
        out += PASSWORD_ALPHABET[bytes[i]! % PASSWORD_ALPHABET.length];
      }
      return out;
    },
  };
}

export const hostFs: HostFs = {
  async writeFile(path, content, opts) {
    await fs.writeFile(path, content, opts?.mode ? { mode: opts.mode } : 'utf8');
  },
  async readFile(path) {
    return fs.readFile(path, 'utf8');
  },
  async exists(path) {
    try {
      await fs.access(path);
      return true;
    } catch {
      return false;
    }
  },
  async mkdir(path, opts) {
    await fs.mkdir(path, opts);
  },
  async remove(path) {
    await fs.rm(path, { recursive: true, force: true });
  },
};

/**
 * Execute a command without a shell.
 *
 * args are passed as an array on purpose: never build a command line by
 * concatenating strings. A business name containing a quote or semicolon
 * would otherwise be able to inject shell commands into the host that
 * holds the Docker socket.
 */
export function createCommandRunner(): ProvisioningDeps['runCommand'] {
  return (cmd, args, opts) =>
    new Promise<CommandResult>((resolve, reject) => {
      execFile(
        cmd,
        args,
        {
          cwd: opts?.cwd,
          env: opts?.env ? { ...process.env, ...opts.env } : process.env,
          timeout: 15 * 60 * 1000,
          maxBuffer: 10 * 1024 * 1024,
          shell: false,
          windowsHide: true,
        },
        (error, stdout, stderr) => {
          if (error && typeof (error as { code?: unknown }).code !== 'number') {
            // Failed to spawn at all (binary missing, permission denied).
            reject(new Error(`Failed to run ${cmd}: ${error.message}`));
            return;
          }
          const code =
            error && typeof (error as { code?: unknown }).code === 'number'
              ? Number((error as { code: number }).code)
              : 0;
          resolve({ code, stdout: String(stdout), stderr: String(stderr) });
        },
      );
    });
}

export const httpPort: ProvisioningDeps['http'] = {
  async get(url, opts) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts?.timeoutMs ?? 5000);
    try {
      const res = await fetch(url, { signal: controller.signal });
      const text = await res.text();
      let body: unknown = text;
      try {
        body = JSON.parse(text);
      } catch {
        // Not JSON; keep the raw text for diagnostics.
      }
      return { status: res.status, body };
    } finally {
      clearTimeout(timer);
    }
  },
};
