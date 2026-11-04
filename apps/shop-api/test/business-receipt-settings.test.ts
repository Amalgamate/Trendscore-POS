import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { businessRouter } from '../src/modules/business/business.router';

const ids = vi.hoisted(() => ({
  business: '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa',
  user: 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f',
}));

const mocks = vi.hoisted(() => ({
  prisma: {
    user: { findUnique: vi.fn() },
    businessSetting: {
      findUnique: vi.fn(),
      upsert: vi.fn(),
    },
  },
}));

vi.mock('../src/lib/prisma', () => ({ prisma: mocks.prisma }));

const secret = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';

describe('receipt customer-name setting', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.prisma.user.findUnique.mockImplementation(async () => ({
      id: ids.user,
      fullName: 'Settings User',
      role: 'OWNER',
      active: true,
      mustChangePin: false,
    }));
    mocks.prisma.businessSetting.findUnique.mockResolvedValue(null);
    mocks.prisma.businessSetting.upsert.mockImplementation(async ({
      update,
      where,
    }: {
      update: { value: boolean };
      where: { businessId_key: { businessId: string; key: string } };
    }) => ({
      ...where.businessId_key,
      value: update.value,
    }));

    const app = express();
    app.use(express.json());
    app.use('/business', businessRouter(ids.business));
    server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const address = server.address();
    if (!address || typeof address === 'string') {
      throw new Error('No test server address');
    }
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  });

  function auth(role = 'OWNER') {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ids.user,
      fullName: 'Settings User',
      role,
      active: true,
      mustChangePin: false,
    });
    return jwt.sign({ sub: ids.user }, secret);
  }

  it('defaults receipt customer names to visible when the setting is absent', async () => {
    const response = await fetch(
      `${baseUrl}/business/settings/receipt.showCustomerName`,
      { headers: { Authorization: `Bearer ${auth()}` } },
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      key: 'receipt.showCustomerName',
      value: true,
    });
  });

  it('allows an owner to change the typed setting value', async () => {
    const response = await fetch(
      `${baseUrl}/business/settings/receipt.showCustomerName`,
      {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${auth()}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ value: false }),
      },
    );
    expect(response.status).toBe(200);
    expect(mocks.prisma.businessSetting.upsert).toHaveBeenCalledWith({
      where: {
        businessId_key: {
          businessId: ids.business,
          key: 'receipt.showCustomerName',
        },
      },
      update: { value: false },
      create: {
        businessId: ids.business,
        key: 'receipt.showCustomerName',
        value: false,
      },
    });
  });

  it('rejects a non-boolean value and limits writes to owners', async () => {
    const badValue = await fetch(
      `${baseUrl}/business/settings/receipt.showCustomerName`,
      {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${auth()}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ value: 'yes' }),
      },
    );
    expect(badValue.status).toBe(422);

    const managerWrite = await fetch(
      `${baseUrl}/business/settings/receipt.showCustomerName`,
      {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${auth('MANAGER')}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ value: false }),
      },
    );
    expect(managerWrite.status).toBe(403);
    expect(mocks.prisma.businessSetting.upsert).not.toHaveBeenCalled();
  });
});
