/**
 * Provisioning engine — types and contracts.
 *
 * Design rule: the engine must be provable without Docker. Every side
 * effect (running a command, writing a file, calling an HTTP endpoint)
 * goes through an injected port, so the orchestration logic can be
 * tested in-process and deterministically.
 *
 * The same code backs both the Phase 1 CLI (proving provisioning by hand)
 * and the later POST /control/instances endpoint. There is only ever one
 * implementation.
 */

export type StepStatus = 'PENDING' | 'RUNNING' | 'SUCCEEDED' | 'FAILED' | 'SKIPPED';

export interface StepDefinition {
  /** Stable machine key, persisted in provisioning_steps.step_key. */
  key: StepKey;
  /** Copy shown to the shop owner on the provisioning screen. */
  displayName: string;
  /** Ordering. Lower runs first. */
  position: number;
  /**
   * Whether the owner sees this step. Hidden steps are still recorded and
   * still appear in the control plane, so support can explain what happened
   * without lying to the customer about what they are seeing.
   */
  customerVisible: boolean;
  /** Performs the work. Throwing marks the step FAILED. */
  execute(ctx: ProvisioningContext, deps: ProvisioningDeps): Promise<StepOutcome>;
  /**
   * Undo, run when a later step fails or an operator deprovisions.
   * Must be safe to call when the step never completed.
   */
  rollback?(ctx: ProvisioningContext, deps: ProvisioningDeps): Promise<void>;
}

export interface StepOutcome {
  message?: string;
  /** Artefacts other steps may need, e.g. generated credentials. */
  data?: Record<string, unknown>;
}

/** Everything the engine needs to know about the shop being built. */
export interface ProvisioningContext {
  instanceId: string;
  /** Short id used in logs and support tickets. */
  shortId: string;
  businessName: string;
  /** URL-safe subdomain, e.g. "james-mini-mart". */
  slug: string;
  hostname: string;
  ownerName: string;
  ownerPhone: string;
  ownerEmail?: string;
  businessType?: string;
  location?: string;
  /** Pinned immutable image tags. Never :latest. */
  backendImage: string;
  frontendImage: string;
  version: string;
  /** Host to deploy onto. */
  host: { name: string; region: string; dockerSocketPath: string };
  /** Absolute path on the host holding this instance's state. */
  instanceDir: string;
  region: string;
  /** Memory ceiling for this instance's containers. Defaults to 1024M. */
  resourceMemoryMb?: number;
}

export interface ProvisioningDeps {
  /** Run a shell command on the target host. */
  runCommand: (cmd: string, args: string[], opts?: { cwd?: string; env?: Record<string, string> }) => Promise<CommandResult>;
  /** Read/write/delete files on the target host. */
  fs: HostFs;
  /** Health probe against the instance once it is up. */
  http: {
    get: (url: string, opts?: { timeoutMs?: number }) => Promise<HttpResult>;
  };
  /** Secrets source. Never log or echo what this returns. */
  secrets: SecretGenerator;
  /** Optional bootstrap administrator applied to each new shop instance. */
  platformSuperAdmin?: { phone: string; initialPin: string };
  /** Structured logging; secrets must never be passed to this. */
  log: (level: 'info' | 'warn' | 'error', msg: string, meta?: Record<string, unknown>) => void;
  /** Emitted after each step so the onboarding screen can stream progress. */
  onStepChange?: (step: StepKey, status: StepStatus, message?: string) => void | Promise<void>;
  /** Simulated timings for tests. */
  sleep?: (ms: number) => Promise<void>;
}

export interface CommandResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface HttpResult {
  status: number;
  body: unknown;
}

export interface HostFs {
  writeFile(path: string, content: string, opts?: { mode?: number }): Promise<void>;
  readFile(path: string): Promise<string>;
  exists(path: string): Promise<boolean>;
  mkdir(path: string, opts?: { recursive?: boolean; mode?: number }): Promise<void>;
  remove(path: string): Promise<void>;
}

export interface SecretGenerator {
  /** URL-safe random token. */
  token(bytes?: number): string;
  /** Postgres superuser-style password, restricted charset. */
  password(length?: number): string;
  /** Base64 for auth material. */
  base64(bytes?: number): string;
}

export type StepKey =
  | 'validate'
  | 'instance_id'
  | 'directory'
  | 'credentials'
  | 'compose'
  | 'network'
  | 'postgres'
  | 'redis'
  | 'backend'
  | 'frontend'
  | 'migrations'
  | 'seed'
  | 'owner'
  | 'platform_admin'
  | 'domain'
  | 'tls'
  | 'health_check'
  | 'backup'
  | 'register';

export interface StepRecord {
  key: StepKey;
  displayName: string;
  position: number;
  customerVisible: boolean;
  status: StepStatus;
  message?: string;
  errorDetail?: string;
  startedAt?: Date;
  finishedAt?: Date;
  data?: Record<string, unknown>;
}
