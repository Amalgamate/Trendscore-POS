import type {
  CommandResult,
  HostFs,
  ProvisioningContext,
  ProvisioningDeps,
  SecretGenerator,
  StepRecord,
} from '../../src/modules/provisioning/types.js';

/** Deterministic fakes so the engine can be tested without Docker. */

export function makeContext(over: Partial<ProvisioningContext> = {}): ProvisioningContext {
  return {
    instanceId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    shortId: 'aaaaaa',
    businessName: 'James Mini Mart',
    slug: 'james-mini-mart',
    hostname: 'james-mini-mart.retailos.local',
    ownerName: 'James Kamau',
    ownerPhone: '254712345678',
    businessType: 'GENERAL_RETAIL',
    location: 'Nairobi',
    backendImage: 'ghcr.io/acme/shop-api:0.1.0',
    frontendImage: 'ghcr.io/acme/shop-pos:0.1.0',
    version: '0.1.0',
    host: { name: 'test-host', region: 'ke-nairobi-1', dockerSocketPath: '/var/run/docker.sock' },
    instanceDir: '/tmp/instances/aaaaaa',
    region: 'ke-nairobi-1',
    resourceMemoryMb: 1024,
    ...over,
  };
}

export class FakeFs implements HostFs {
  files = new Map<string, string>();
  dirs: string[] = [];
  removed: string[] = [];

  async writeFile(path: string, content: string, opts?: { mode?: number }) {
    this.files.set(path, content);
  }
  async readFile(path: string) {
    const v = this.files.get(path);
    if (v === undefined) throw new Error(`ENOENT: ${path}`);
    return v;
  }
  async exists(path: string) {
    return this.files.has(path) || this.dirs.includes(path);
  }
  async mkdir(path: string) {
    this.dirs.push(path);
  }
  async remove(path: string) {
    this.removed.push(path);
    this.dirs = this.dirs.filter((d) => d !== path);
  }
}

export class FakeSecrets implements SecretGenerator {
  private n = 0;
  token(bytes = 24) {
    this.n += 1;
    return `tok${this.n}${'x'.repeat(Math.max(0, bytes - 3))}`;
  }
  base64(bytes = 32) {
    return `b64-${'y'.repeat(bytes)}`;
  }
  password(length = 32) {
    return 'p'.repeat(length);
  }
}

export interface Recorder {
  deps: ProvisioningDeps;
  commands: string[];
  fs: FakeFs;
  /** Make commands matching a substring fail. */
  failOn: (needle: string, stderr?: string) => void;
  /** Force HTTP probe results, in order. */
  httpStatuses: number[];
  events: Array<{ key: string; status: string }>;
}

export function makeDeps(over: Partial<ProvisioningDeps> = {}): Recorder {
  const commands: string[] = [];
  const fs = new FakeFs();
  const failures = new Map<string, string>();
  const httpStatuses: number[] = [];
  const events: Array<{ key: string; status: string }> = [];

  const deps: ProvisioningDeps = {
    runCommand: async (cmd, args) => {
      const line = `${cmd} ${args.join(' ')}`;
      commands.push(line);
      for (const [needle, stderr] of failures) {
        if (line.includes(needle)) return { code: 1, stdout: '', stderr };
      }
      return { code: 0, stdout: 'ok', stderr: '' } satisfies CommandResult;
    },
    fs,
    http: {
      get: async () => {
        const next = httpStatuses.shift();
        if (next === undefined) return { status: 200, body: {} };
        if (next >= 400) throw new Error(`probe failed with ${next}`);
        return { status: next, body: {} };
      },
    },
    secrets: new FakeSecrets(),
    log: () => undefined,
    onStepChange: (key, status) => {
      events.push({ key, status });
    },
    sleep: async () => undefined,
    ...over,
  };

  return {
    deps,
    commands,
    fs,
    httpStatuses,
    events,
    failOn: (needle, stderr = 'simulated failure') => failures.set(needle, stderr),
  };
}

export function succeeded(resumeFrom: StepRecord[], keys: string[]): StepRecord[] {
  return keys.map((key, i) => ({
    key: key as StepRecord['key'],
    displayName: key,
    position: i * 10,
    customerVisible: true,
    status: 'SUCCEEDED',
  }));
}
