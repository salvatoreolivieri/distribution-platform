import type { components } from './generated/common';

export type ApiError = components['schemas']['ApiError'];

/** Thrown for every non-2xx response; carries the error envelope from common.yaml. */
export class ApiRequestError extends Error {
  constructor(
    readonly status: number,
    readonly error: ApiError,
  ) {
    super(`${error.code}: ${error.message}`);
  }
}

export interface TokenStore {
  accessToken(): string | null;
  /** Exchanges the refresh token for a new pair. Returns false when the session is over. */
  refresh(): Promise<boolean>;
}

/**
 * fetch wrapper: adds the bearer token, unwraps { data }, and on a 401 refreshes the token
 * once and retries the request.
 */
export function createClient(baseUrl: string, tokens: TokenStore) {
  async function send(path: string, init: RequestInit, retried: boolean): Promise<Response> {
    const headers = new Headers(init.headers);
    const token = tokens.accessToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
    if (init.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');

    const res = await fetch(baseUrl + path, { ...init, headers });
    if (res.status === 401 && !retried && (await tokens.refresh())) {
      return send(path, init, true);
    }
    return res;
  }

  return async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const res = await send(path, init, false);
    if (res.status === 204) return undefined as T;
    const body: unknown = await res.json().catch(() => null);
    if (!res.ok) {
      const error = (body as { error?: ApiError } | null)?.error ?? {
        code: 'INTERNAL',
        message: `HTTP ${res.status}`,
      };
      throw new ApiRequestError(res.status, error);
    }
    return (body as { data: T }).data;
  };
}
