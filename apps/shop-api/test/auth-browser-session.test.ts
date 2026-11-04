import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import { createServer, type Server } from 'node:http';
import { authRouter } from '../src/modules/auth/auth.router';

const mocks = vi.hoisted(() => ({
  userFindUnique: vi.fn(),
  userUpdate: vi.fn(),
  verifyPin: vi.fn(),
  hashPin: vi.fn(),
}));

vi.mock('../src/lib/prisma', () => ({
  prisma: {
    user: {
      findUnique: mocks.userFindUnique,
      update: mocks.userUpdate,
    },
  },
}));

vi.mock('argon2', () => ({
  default: {
    verify: mocks.verifyPin,
    hash: mocks.hashPin,
  },
}));

function sessionCookie(response: Response): string {
  const setCookie = response.headers.get('set-cookie');
  if (!setCookie) throw new Error('Login did not set a session cookie');
  return setCookie.split(';')[0]!;
}

describe('browser authentication session', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.verifyPin.mockResolvedValue(true);
    mocks.hashPin.mockResolvedValue('new-pin-hash');
    mocks.userFindUnique.mockResolvedValue({
      id: 'user-1',
      fullName: 'Shop Owner',
      phone: '254700000001',
      role: 'OWNER',
      active: true,
      mustChangePin: false,
      pinHash: 'pin-hash',
    });
    mocks.userUpdate.mockResolvedValue({});

    const app = express();
    app.use(express.json());
    app.use('/auth', authRouter());
    server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('No test server address');
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  });

  it('sets an HttpOnly cookie and omits the JavaScript-readable JWT for web login', async () => {
    const response = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Use-HttpOnly-Cookie': 'true',
      },
      body: JSON.stringify({ phone: '254700000001', pin: '1234' }),
    });
    const body = await response.json() as Record<string, unknown>;
    const cookie = response.headers.get('set-cookie') ?? '';

    expect(response.status).toBe(200);
    expect(body).not.toHaveProperty('token');
    expect(body.user).toMatchObject({ id: 'user-1', role: 'OWNER' });
    expect(cookie).toContain('retailpos_session=');
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('SameSite=Strict');
    expect(cookie).toContain('Path=/');
  });

  it('keeps bearer-token login for native clients', async () => {
    const response = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '254700000001', pin: '1234' }),
    });
    const body = await response.json() as Record<string, unknown>;

    expect(response.status).toBe(200);
    expect(body.token).toEqual(expect.any(String));
    expect(response.headers.get('set-cookie')).toBeNull();
  });

  it('restores the current server profile from the browser cookie', async () => {
    const tokenResponse = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Use-HttpOnly-Cookie': 'true',
      },
      body: JSON.stringify({ phone: '254700000001', pin: '1234' }),
    });
    const cookie = sessionCookie(tokenResponse);

    const response = await fetch(`${baseUrl}/auth/session`, {
      headers: { Cookie: cookie },
    });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      user: expect.objectContaining({
        id: 'user-1',
        fullName: 'Shop Owner',
        role: 'OWNER',
        mustChangePin: false,
      }),
    });
  });

  it('checks request origin for cookie-authenticated writes and clears the cookie on logout', async () => {
    const tokenResponse = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Use-HttpOnly-Cookie': 'true',
      },
      body: JSON.stringify({ phone: '254700000001', pin: '1234' }),
    });
    const cookie = sessionCookie(tokenResponse);
    mocks.userUpdate.mockClear();
    const rejected = await fetch(`${baseUrl}/auth/change-pin`, {
      method: 'POST',
      headers: { Cookie: cookie, 'Content-Type': 'application/json' },
      body: JSON.stringify({ pin: '5678' }),
    });
    expect(rejected.status).toBe(403);
    expect(mocks.userUpdate).not.toHaveBeenCalled();

    const logout = await fetch(`${baseUrl}/auth/logout`, {
      method: 'POST',
      headers: { Cookie: cookie },
    });
    expect(logout.status).toBe(200);
    expect(logout.headers.get('set-cookie')).toContain('retailpos_session=;');
  });
});
