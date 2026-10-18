import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiRequestError, createClient } from './client';

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

afterEach(() => vi.unstubAllGlobals());

describe('createClient', () => {
  it('unwraps data and sends the bearer token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(json(200, { data: { ok: true } }));
    vi.stubGlobal('fetch', fetchMock);
    const request = createClient('', { accessToken: () => 't1', refresh: async () => false });

    await expect(request('/v1/jobs')).resolves.toEqual({ ok: true });
    const headers = fetchMock.mock.calls[0]?.[1]?.headers as Headers;
    expect(headers.get('Authorization')).toBe('Bearer t1');
  });

  it('refreshes once on 401 and retries', async () => {
    let token = 'old';
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(401, { error: { code: 'UNAUTHENTICATED', message: 'expired' } }))
      .mockResolvedValueOnce(json(200, { data: 1 }));
    vi.stubGlobal('fetch', fetchMock);
    const refresh = vi.fn(async () => {
      token = 'new';
      return true;
    });
    const request = createClient('', { accessToken: () => token, refresh });

    await expect(request('/v1/jobs')).resolves.toBe(1);
    expect(refresh).toHaveBeenCalledOnce();
    expect((fetchMock.mock.calls[1]?.[1]?.headers as Headers).get('Authorization')).toBe('Bearer new');
  });

  it('throws the error envelope', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(json(403, { error: { code: 'FORBIDDEN', message: 'no' } })));
    const request = createClient('', { accessToken: () => null, refresh: async () => false });

    await expect(request('/v1/jobs')).rejects.toMatchObject({ status: 403, error: { code: 'FORBIDDEN' } });
    await expect(request('/v1/jobs')).rejects.toBeInstanceOf(ApiRequestError);
  });
});
